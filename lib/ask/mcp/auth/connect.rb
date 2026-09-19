# frozen_string_literal: true

require "securerandom"
require "digest"
require "uri"

module Ask
  module MCP
    module Auth
      # The browser dance that gives one person a credential for an MCP
      # server: discover the authorization server behind the protected
      # resource, register this client when the server allows it, hand the
      # host a URL to send the browser to, and redeem the redirected code
      # for tokens.
      #
      # Built for hosts that drive a real browser — a web action redirects
      # to #authorization_url and its callback redeems the code — so the
      # class keeps no browser state of its own. The caller carries the
      # state and the PKCE verifier between the two steps, and persists
      # #registered_client when dynamic registration produced one.
      class Connect
        class Error < StandardError; end

        attr_reader :endpoint, :registered_client

        def initialize(endpoint:, client_id: nil, client_secret: nil, http: Http)
          @endpoint = endpoint
          @client_id = client_id
          @client_secret = client_secret
          @http = http
          @metadata = nil
          @registered_client = nil
        end

        # The URL to send the browser to, with the PKCE verifier the caller
        # must keep until the callback. The scope comes from the server's
        # own advertised scopes unless the caller names one.
        def authorization_url(redirect_uri:, state:, scope: nil, code_verifier: nil)
          metadata = discover!
          client = ensure_client!(redirect_uri)
          verifier = code_verifier || self.class.generate_verifier

          params = {
            response_type: "code",
            client_id: client[:client_id],
            redirect_uri: redirect_uri,
            state: state,
            code_challenge: pkce_challenge(verifier),
            code_challenge_method: "S256"
          }
          params[:scope] = scope || metadata[:scopes_supported]&.join(" ") || "mcp"

          {url: "#{metadata[:authorization_endpoint]}?#{URI.encode_www_form(params)}", code_verifier: verifier}
        end

        # Redeem the redirected code. The same verifier the authorization
        # step handed back comes along; the answer is the caller's token to
        # store against whoever consented.
        def exchange(code:, verifier:, redirect_uri:)
          metadata = discover!
          client = ensure_client!(redirect_uri)

          params = {
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri,
            client_id: client[:client_id],
            code_verifier: verifier
          }
          params[:client_secret] = client[:client_secret] if client[:client_secret]

          token_response(@http.post_json(metadata[:token_endpoint], params))
        end

        # A fresh access token from the refresh token the server handed out.
        def refresh(refresh_token:)
          metadata = discover!
          client = ensure_client!

          params = {
            grant_type: "refresh_token",
            refresh_token: refresh_token,
            client_id: client[:client_id]
          }
          params[:client_secret] = client[:client_secret] if client[:client_secret]

          token_response(@http.post_json(metadata[:token_endpoint], params))
        end

        # Walk the chain MCP defines: the resource server names its
        # authorization servers, and one of them names its endpoints. A
        # server that publishes nothing is its own authorization server.
        def discover!
          return @metadata if @metadata

          issuer = authorization_server_for(endpoint)
          document = authorization_server_metadata(issuer)
          unless document && document[:authorization_endpoint] && document[:token_endpoint]
            raise Error, "no authorization server metadata at #{issuer}"
          end

          @metadata = {
            issuer: issuer,
            authorization_endpoint: document[:authorization_endpoint],
            token_endpoint: document[:token_endpoint],
            registration_endpoint: document[:registration_endpoint],
            scopes_supported: document[:scopes_supported]
          }
        end

        # The client this server knows us by: pre-registered credentials
        # when the host has them, otherwise a registration the server
        # created on the spot. The registered client is exposed for the
        # host to persist — a registration that is remembered is one that
        # is never asked for twice.
        def ensure_client!(redirect_uri = nil)
          return {client_id: @client_id, client_secret: @client_secret}.compact if @client_id

          registration = @metadata && @metadata[:registration_endpoint]
          raise Error, "no client credentials and #{endpoint} does not allow registration" unless registration
          raise Error, "dynamic registration needs a redirect_uri" unless redirect_uri

          @registered_client ||= begin
            document = @http.post_json(registration, registration_params(redirect_uri))
            {client_id: document[:client_id], client_secret: document[:client_secret]}.compact
          end
        end

        def self.generate_verifier
          Base64.urlsafe_encode64(SecureRandom.random_bytes(64)).delete("=")
        end

        def self.pkce_challenge(verifier)
          Base64.urlsafe_encode64(Digest::SHA256.digest(verifier)).delete("=")
        end

        private

        attr_reader :http

        def registration_params(redirect_uri)
          {
            client_name: "Anychat",
            redirect_uris: [redirect_uri],
            grant_types: %w[authorization_code refresh_token],
            response_types: %w[code],
            token_endpoint_auth_method: "none",
            application_type: "web"
          }
        end

        def pkce_challenge(verifier)
          self.class.pkce_challenge(verifier)
        end

        # RFC 9728: the resource server publishes its metadata under its own
        # well-known path. The RFC allows the root form and a path-suffixed
        # form; a server that publishes neither is treated as its own
        # authorization server, which is how single-server setups behave.
        def authorization_server_for(url)
          uri = URI.parse(url.to_s)
          candidates = [
            well_known_uri(uri, "oauth-protected-resource"),
            well_known_uri(uri, "oauth-protected-resource", suffix_path: uri.path)
          ].compact

          document = candidates.filter_map { |candidate| http.get_json(candidate) rescue nil }.first
          servers = document && (document[:authorization_servers] || document["authorization_servers"])
          Array(servers).first || "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? "" : ":#{uri.port}"}"
        rescue URI::InvalidURIError
          raise Error, "not a usable endpoint: #{endpoint.inspect}"
        end

        # RFC 8414 and OIDC discovery, same bargain: try the standard
        # placements and take the first that answers.
        def authorization_server_metadata(issuer)
          issuer_uri = URI.parse(issuer.to_s)
          [
            well_known_uri(issuer_uri, "oauth-authorization-server"),
            well_known_uri(issuer_uri, "oauth-authorization-server", suffix_path: issuer_uri.path),
            well_known_uri(issuer_uri, "openid-configuration")
          ].compact.filter_map { |candidate| http.get_json(candidate) rescue nil }.first
        end

        def well_known_uri(uri, name, suffix_path: nil)
          path = suffix_path.to_s.sub(%r{/\z}, "")
          base = "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? "" : ":#{uri.port}"}"
          if path.empty?
            "#{base}/.well-known/#{name}"
          else
            "#{base}/.well-known/#{name}#{path}"
          end
        end

        def token_response(response)
          unless response[:access_token]
            raise Error, "token request did not return an access_token"
          end

          {
            access_token: response[:access_token],
            refresh_token: response[:refresh_token],
            expires_at: response[:expires_in] ? Time.now + response[:expires_in].to_i : nil,
            scope: response[:scope]
          }
        end

        # A thin HTTP seam, so a host can bring its own client and tests can
        # stay off the network. Form-encoded bodies, because that is what
        # authorization servers speak at these endpoints.
        module Http
          module_function

          def get_json(url)
            require "httpx"

            response = HTTPX.get(url)
            return nil unless response.status == 200

            JSON.parse(response.body.to_s, symbolize_names: true)
          rescue JSON::ParserError
            nil
          end

          def post_json(url, params)
            require "httpx"

            response = HTTPX.post(url, form: params)
            unless response.status == 200 || response.status == 201
              raise Error, "request to #{url} failed: #{response.status} #{response.body.to_s[0, 200]}"
            end

            JSON.parse(response.body.to_s, symbolize_names: true)
          rescue JSON::ParserError
            raise Error, "invalid JSON from #{url}"
          end
        end
      end
    end
  end
end
