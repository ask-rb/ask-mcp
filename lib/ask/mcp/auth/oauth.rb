# frozen_string_literal: true

module Ask
  module MCP
    module Auth
      class OAuth
        attr_reader :client_id, :client_secret, :token_url, :auth_url, :issuer

        def initialize(client_id:, client_secret: nil, token_url: nil, auth_url: nil,
                       redirect_uri: nil, scopes: [], issuer: nil, discovery_url: nil)
          @client_id = client_id
          @client_secret = client_secret
          @token_url = token_url
          @auth_url = auth_url
          @redirect_uri = redirect_uri
          @scopes = scopes
          @issuer = issuer
          @discovery_url = discovery_url
          @access_token = nil
          @refresh_token = nil
          @expires_at = nil
        end

        def authenticated?
          !@access_token.nil? && !expired?
        end

        def apply(headers = {})
          headers.merge("Authorization" => "Bearer #{@access_token}")
        end

        def authenticate!
          if @client_secret && @token_url
            authenticate_client_credentials
          elsif @auth_url
            authenticate_authorization_code
          elsif @issuer || @discovery_url
            raise AuthError, "Call #discover! before #authenticate! to resolve endpoints"
          else
            raise AuthError, "No authentication method available"
          end
          self
        end

        def refresh!
          raise AuthError, "No refresh token available" unless @refresh_token
          perform_token_refresh
          self
        end

        # Validate an `iss` parameter from an authorization response
        # (RFC 9207, 2026-07-28): when an issuer is recorded (via
        # discovery or configuration), a present `iss` MUST match it.
        # Call before redeeming an authorization code.
        def validate_iss!(iss)
          return self if @issuer.nil?
          raise AuthError, "iss mismatch: expected #{@issuer}, got #{iss.inspect}" unless iss.to_s == @issuer.to_s
          self
        end

        # Discover authorization server endpoints via OpenID Connect Discovery
        # 1.0 (2025-11-25, SEP-797). Fetches the document at discovery_url (or
        # the well-known URL derived from issuer per RFC 8414) and populates
        # token_url, auth_url, and issuer. Returns self.
        def discover!(discovery_url: nil)
          require "httpx"

          url = discovery_url || @discovery_url || well_known_discovery_url
          data = fetch_json(HTTPX, url)

          @issuer = data[:issuer] if data[:issuer]
          @token_url = data[:token_endpoint] if data[:token_endpoint]
          @auth_url = data[:authorization_endpoint] if data[:authorization_endpoint]

          raise AuthError, "Discovery document has no token_endpoint" unless @token_url
          self
        end

        private

        def well_known_discovery_url
          return @discovery_url if @discovery_url
          raise AuthError, "OIDC discovery requires an issuer or discovery_url" unless @issuer
          "#{@issuer.sub(%r{/+\z}, "")}/.well-known/openid-configuration"
        end

        def fetch_json(http, url)
          response = http.get(url)
          unless response.status == 200
            raise AuthError, "Discovery request failed: #{response.status} #{response.body.to_s[0..200]}"
          end
          JSON.parse(response.body.to_s, symbolize_names: true)
        rescue JSON::ParserError => e
          raise AuthError, "Invalid discovery document: #{e.message}"
        end

        def expired?
          @expires_at && Time.now >= @expires_at
        end

        def authenticate_client_credentials
          require "httpx"

          response = HTTPX.post(@token_url, json: {
            grant_type: "client_credentials",
            client_id: @client_id,
            client_secret: @client_secret,
            scope: @scopes.join(" ") || "mcp"
          })

          handle_token_response(response)
        end

        def authenticate_authorization_code
          raise AuthError, "Authorization code flow requires a redirect URI" unless @redirect_uri
          raise AuthError, "Authorization code flow must be completed interactively"

          # The authorization code flow requires user interaction.
          # This is a placeholder for the interactive flow that would:
          # 1. Open the auth URL in a browser
          # 2. Listen for the redirect with the auth code
          # 3. Exchange the code for tokens
        end

        def perform_token_refresh
          require "httpx"

          response = HTTPX.post(@token_url, json: {
            grant_type: "refresh_token",
            refresh_token: @refresh_token,
            client_id: @client_id,
            client_secret: @client_secret
          })

          handle_token_response(response)
        end

        def handle_token_response(response)
          unless response.status == 200
            raise AuthError, "Token request failed: #{response.status} #{response.body.to_s[0..200]}"
          end

          data = JSON.parse(response.body.to_s, symbolize_names: true)
          @access_token = data[:access_token]
          @refresh_token = data[:refresh_token]
          @expires_at = data[:expires_in] ? Time.now + data[:expires_in].to_i : nil
        rescue JSON::ParserError => e
          raise AuthError, "Invalid token response: #{e.message}"
        end
      end
    end
  end
end
