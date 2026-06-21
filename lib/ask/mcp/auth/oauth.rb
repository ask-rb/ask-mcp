# frozen_string_literal: true

module Ask
  module MCP
    module Auth
      class OAuth
        attr_reader :client_id, :client_secret, :token_url, :auth_url

        def initialize(client_id:, client_secret: nil, token_url:, auth_url: nil,
                       redirect_uri: nil, scopes: [])
          @client_id = client_id
          @client_secret = client_secret
          @token_url = token_url
          @auth_url = auth_url
          @redirect_uri = redirect_uri
          @scopes = scopes
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
          if @client_secret
            authenticate_client_credentials
          elsif @auth_url
            authenticate_authorization_code
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

        private

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
