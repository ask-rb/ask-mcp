# frozen_string_literal: true

require_relative "test_helper"

class ServerTest < Minitest::Test
  def test_server_construction
    tool = Ask::MCP::Tool.new(name: "ping", description: "Ping pong")
    server = Ask::MCP::Server.new(
      name: "test-server",
      version: "1.0.0",
      capabilities: { tools: {} },
      tools: { "ping" => tool }
    )
    assert_equal "test-server", server.name
    assert_equal "1.0.0", server.version
    assert_equal ["ping"], server.tool_names
    assert server.capabilities.key?(:tools)
  end

  def test_server_to_h
    server = Ask::MCP::Server.new(
      name: "empty-server",
      capabilities: { tools: {} }
    )
    h = server.to_h
    assert_equal "empty-server", h[:name]
    assert_equal [], h[:tools]
  end
end
