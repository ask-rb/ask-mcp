# frozen_string_literal: true

require_relative "test_helper"
require "json"

module Ask
  module MCP
    module Auth
      class ConnectTest < Minitest::Test
        ENDPOINT = "https://mcp.example.com/api"

        # A scripted HTTP seam: each request is answered by a lambda.
        class FakeHttp
          attr_reader :calls

          def initialize
            @calls = []
            @routes = []
          end

          def on(method, url_prefix, result)
            @routes << [method, url_prefix, result]
          end

          def get_json(url)
            @calls << [:get_json, url, nil]
            answer_for(:get_json, url)
          end

          def post_json(url, params)
            @calls << [:post_json, url, params]
            answer_for(:post_json, url)
          end

          private

          def answer_for(method, url)
            route = @routes.find { |m, prefix, _| m == method && url.start_with?(prefix) }
            result = route && route[2]
            result.is_a?(Proc) ? result.call : result
          end
        end

        def server_metadata
          {
            issuer: "https://auth.example.com",
            authorization_endpoint: "https://auth.example.com/authorize",
            token_endpoint: "https://auth.example.com/token",
            registration_endpoint: "https://auth.example.com/register",
            scopes_supported: %w[repo read:user]
          }
        end

        def flow(http: nil, client_id: nil, client_secret: nil)
          Connect.new(endpoint: ENDPOINT, client_id: client_id, client_secret: client_secret, http: http)
        end

        def test_discovery_walks_the_protected_resource_to_the_authorization_
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-protected-resource",
            {authorization_servers: ["https://auth.example.com"]}
          http.on :get_json, "https://auth.example.com/.well-known/oauth-authorization-server", server_metadata

          metadata = flow(http: http).discover!

          assert_equal "https://auth.example.com/authorize", metadata[:authorization_endpoint]
          assert_equal "https://auth.example.com/token", metadata[:token_endpoint]
          assert_equal %w[repo read:user], metadata[:scopes_supported]
        end

        def test_a_server_with_no_resource_metadata_is_treated_as_its_own_aut
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-protected-resource", -> { raise "404" }
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server",
            server_metadata.merge(issuer: "https://mcp.example.com",
              authorization_endpoint: "https://mcp.example.com/authorize",
              token_endpoint: "https://mcp.example.com/token")

          metadata = flow(http: http).discover!

          assert_equal "https://mcp.example.com/authorize", metadata[:authorization_endpoint]
        end

        def test_a_server_with_no_metadata_anywhere_fails_discovery
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-protected-resource", -> { raise "404" }

          assert_raises(Connect::Error) { flow(http: http).discover! }
        end

        def test_the_authorization_url_carries_the_client_pkce_and_the_server
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-protected-resource", -> { raise "404" }
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server", server_metadata

          outcome = flow(http: http, client_id: "client-1")
            .authorization_url(redirect_uri: "https://app.example.com/callback", state: "st-1")

          uri = URI.parse(outcome[:url])
          params = URI.decode_www_form(uri.query).to_h
          assert_equal "https://auth.example.com/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
          assert_equal "code", params["response_type"]
          assert_equal "client-1", params["client_id"]
          assert_equal "https://app.example.com/callback", params["redirect_uri"]
          assert_equal "st-1", params["state"]
          assert_equal "S256", params["code_challenge_method"]
          assert_equal "repo read:user", params["scope"]
          assert_match(/\A[\w-]{86,}\z/, outcome[:code_verifier])
          challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(outcome[:code_verifier])).delete("=")
          assert_equal challenge, params["code_challenge"]
        end

        def test_an_unregistered_client_registers_on_the_spot_and_the_registr
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server", server_metadata
          http.on :post_json, "https://auth.example.com/register", {
            client_id: "registered-1", client_secret: "secret-1"
          }

          flow = flow(http: http)
          outcome = flow.authorization_url(redirect_uri: "https://app.example.com/callback", state: "st-1")

          params = URI.decode_www_form(URI.parse(outcome[:url]).query).to_h
          assert_equal "registered-1", params["client_id"]
          assert_equal({client_id: "registered-1", client_secret: "secret-1"}, flow.registered_client)
        end

        def test_a_server_that_offers_no_registration_refuses_a_clientless_fl
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server",
            server_metadata.reject { |k, _| k == :registration_endpoint }

          assert_raises(Connect::Error) do
            flow(http: http).authorization_url(redirect_uri: "https://app.example.com/callback", state: "st-1")
          end
        end

        def test_the_code_is_redeemed_at_the_token_endpoint_with_the_verifier
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server", server_metadata
          http.on :post_json, "https://auth.example.com/token",
            {access_token: "token-1", refresh_token: "rt-1", expires_in: 3600}

          flow = flow(http: http, client_id: "client-1")
          outcome = flow.authorization_url(redirect_uri: "https://app.example.com/callback", state: "st-1")

          token = flow.exchange(code: "abc", verifier: outcome[:code_verifier],
            redirect_uri: "https://app.example.com/callback")

          assert_equal "token-1", token[:access_token]
          assert_in_delta 3600, (token[:expires_at] - Time.now), 5
          _, _, params = http.calls.find { |m, u, _| m == :post_json && u.end_with?("/token") }
          assert_equal "authorization_code", params[:grant_type]
          assert_equal "abc", params[:code]
          assert_equal outcome[:code_verifier], params[:code_verifier]
          assert_equal "client-1", params[:client_id]
        end

        def test_a_refresh_grant_returns_a_fresh_token
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server", server_metadata
          http.on :post_json, "https://auth.example.com/token", {access_token: "token-2", expires_in: 60}

          token = flow(http: http, client_id: "client-1").refresh(refresh_token: "rt-1")

          assert_equal "token-2", token[:access_token]
          _, _, params = http.calls.find { |m, u, _| m == :post_json && u.end_with?("/token") }
          assert_equal "refresh_token", params[:grant_type]
          assert_equal "rt-1", params[:refresh_token]
        end

        def test_a_token_response_without_an_access_token_is_an_error
          http = FakeHttp.new
          http.on :get_json, "https://mcp.example.com/.well-known/oauth-authorization-server", server_metadata
          http.on :post_json, "https://auth.example.com/token", {error: "bad_verifier"}

          flow = flow(http: http, client_id: "client-1")
          outcome = flow.authorization_url(redirect_uri: "https://app.example.com/callback", state: "st-1")

          assert_raises(Connect::Error) do
            flow.exchange(code: "abc", verifier: outcome[:code_verifier],
              redirect_uri: "https://app.example.com/callback")
          end
        end
      end
    end
  end
end
