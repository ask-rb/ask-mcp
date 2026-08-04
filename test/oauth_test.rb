# frozen_string_literal: true

require_relative "test_helper"
require "httpx"

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

  # --- OIDC Discovery (2025-11-25) ---

  def fake_response(status, body)
    Struct.new(:status, :body).new(status, body)
  end

  def test_discover_populates_endpoints_from_oidc_document
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "c", issuer: "https://auth.example.com")
    doc = {
      issuer: "https://auth.example.com",
      token_endpoint: "https://auth.example.com/token",
      authorization_endpoint: "https://auth.example.com/auth"
    }.to_json
    HTTPX.stubs(:get)
         .with("https://auth.example.com/.well-known/openid-configuration")
         .returns(fake_response(200, doc))

    oauth.discover!

    assert_equal "https://auth.example.com/token", oauth.token_url
    assert_equal "https://auth.example.com/auth", oauth.auth_url
    assert_equal "https://auth.example.com", oauth.issuer
  end

  def test_discover_uses_explicit_discovery_url
    oauth = Ask::MCP::Auth::OAuth.new(
      client_id: "c",
      discovery_url: "https://auth.example.com/.well-known/openid-configuration"
    )
    doc = { issuer: "https://auth.example.com", token_endpoint: "https://auth.example.com/token" }.to_json
    HTTPX.stubs(:get).returns(fake_response(200, doc))

    oauth.discover!

    assert_equal "https://auth.example.com/token", oauth.token_url
  end

  def test_discover_requires_issuer_or_discovery_url
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "c")
    assert_raises(Ask::MCP::AuthError) { oauth.discover! }
  end

  def test_discover_raises_when_token_endpoint_missing
    oauth = Ask::MCP::Auth::OAuth.new(
      client_id: "c",
      discovery_url: "https://auth.example.com/.well-known/openid-configuration"
    )
    HTTPX.stubs(:get).returns(fake_response(200, { issuer: "https://auth.example.com" }.to_json))
    assert_raises(Ask::MCP::AuthError) { oauth.discover! }
  end

  def test_discover_raises_on_non_200
    oauth = Ask::MCP::Auth::OAuth.new(
      client_id: "c",
      discovery_url: "https://auth.example.com/.well-known/openid-configuration"
    )
    HTTPX.stubs(:get).returns(fake_response(404, "not found"))
    assert_raises(Ask::MCP::AuthError) { oauth.discover! }
  end

  def test_discover_then_client_credentials_authenticates
    oauth = Ask::MCP::Auth::OAuth.new(
      client_id: "c", client_secret: "s",
      discovery_url: "https://auth.example.com/.well-known/openid-configuration"
    )
    doc = { issuer: "https://auth.example.com", token_endpoint: "https://auth.example.com/token" }.to_json
    token = { access_token: "abc123", expires_in: 3600 }.to_json
    HTTPX.stubs(:get).returns(fake_response(200, doc))
    HTTPX.stubs(:post).returns(fake_response(200, token))

    oauth.discover!
    oauth.authenticate!

    assert oauth.authenticated?
    assert_equal "Bearer abc123", oauth.apply({})["Authorization"]
  end

  def test_authenticate_hints_to_discover_when_endpoints_unresolved
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "c", issuer: "https://auth.example.com")
    err = assert_raises(Ask::MCP::AuthError) { oauth.authenticate! }
    assert_match(/discover/i, err.message)
  end

  # --- RFC 9207 iss validation (2026-07-28) ---

  def test_validate_iss_matches_recorded_issuer
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "c", issuer: "https://auth.example.com")
    assert_same oauth, oauth.validate_iss!("https://auth.example.com")
  end

  def test_validate_iss_rejects_mismatch
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "c", issuer: "https://auth.example.com")
    err = assert_raises(Ask::MCP::AuthError) { oauth.validate_iss!("https://evil.example.com") }
    assert_match(/iss mismatch/, err.message)
  end

  def test_validate_iss_passes_without_recorded_issuer
    oauth = Ask::MCP::Auth::OAuth.new(client_id: "c", token_url: "https://auth.example.com/token")
    assert_same oauth, oauth.validate_iss!("https://anything.example.com")
  end
end
