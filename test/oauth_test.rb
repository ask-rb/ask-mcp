# frozen_string_literal: true

require_relative "test_helper"

class OAuthTest < Minitest::Test
  def test_oauth_initialization
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "my-client", token_url: "https://auth.example.com/token")
    assert_equal "my-client", oauth.client_id
    refute oauth.authenticated?
  end

  def test_oauth_with_full_config
    oauth = Ask::MCP::Auth::OAuth.new(
      client_id: "my-client", client_secret: "my-secret",
      token_url: "https://auth.example.com/token",
      auth_url: "https://auth.example.com/auth",
      redirect_uri: "http://localhost/callback", scopes: ["mcp", "read"]
    )
    assert_equal ["mcp", "read"], oauth.instance_variable_get(:@scopes)
  end

  def test_oauth_authenticate_without_method
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "my-client", token_url: "https://auth.example.com/token")
    assert_raises(Ask::MCP::AuthError) { oauth.authenticate! }
  end

  def test_oauth_refresh_without_token
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "my-client", token_url: "https://auth.example.com/token")
    assert_raises(Ask::MCP::AuthError) { oauth.refresh! }
  end
end
