# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  def test_initialize
    transport = Object.new
    client = Ask::MCP::Client.new(transport)
    refute client.initialized?
    assert_equal({}, client.capabilities)
  end

  def test_server_model
    server = Ask::MCP::Server.new(
      name: "filesystem",
      version: "0.1.0",
      capabilities: { tools: {} }
    )
    assert_equal "filesystem", server.name
    assert_empty server.tool_names
    assert_empty server.resource_uris
    assert_empty server.prompt_names
  end

  def test_factory_methods_return_client_instances
    assert_instance_of Ask::MCP::Client, Ask::MCP.from_stdio("echo", ["hello"])
    assert_instance_of Ask::MCP::Client, Ask::MCP.from_sse("http://localhost:8080/sse")
    assert_instance_of Ask::MCP::Client, Ask::MCP.from_http("http://localhost:8080/mcp")
  end

  def test_call_tool_raises_without_start
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    client = Ask::MCP::Client.new(transport, timeout: 1)
    assert_raises(Ask::MCP::ConnectionError) { client.call_tool("test") }
  end

  def test_connect_method
    transport = Object.new
    client = Ask::MCP.connect(transport)
    assert_instance_of Ask::MCP::Client, client
  end
end
