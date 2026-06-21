# frozen_string_literal: true

require_relative "test_helper"

class AuthTokenTest < Minitest::Test
  def test_bearer_token
    token = Ask::MCP::Auth::Token.new("my-secret-token")
    headers = token.apply({})
    assert_equal "Bearer my-secret-token", headers["Authorization"]
  end

  def test_custom_scheme
    token = Ask::MCP::Auth::Token.new("token123", scheme: "Basic")
    headers = token.apply({})
    assert_equal "Basic token123", headers["Authorization"]
  end

  def test_merges_existing_headers
    token = Ask::MCP::Auth::Token.new("secret")
    headers = token.apply({ "Content-Type" => "application/json" })
    assert_equal "application/json", headers["Content-Type"]
    assert_equal "Bearer secret", headers["Authorization"]
  end
end
