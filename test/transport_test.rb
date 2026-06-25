# frozen_string_literal: true

require_relative "test_helper"

class TransportTest < Minitest::Test
  def test_stdio_transport_basics
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    assert_equal "echo", transport.command
    refute transport.running?
  end

  def test_sse_transport_initialization
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    assert_equal "http://localhost:8080/sse", transport.url
    refute transport.running?
  end

  def test_sse_transport_with_options
    transport = Ask::MCP::Transport::SSE.new(
      "http://localhost:8080/sse",
      timeout: 10,
      headers: { "Authorization" => "Bearer token" }
    )
    assert_equal 10, transport.instance_variable_get(:@options)[:timeout]
  end

  def test_streamable_http_initialization
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    assert_equal "http://localhost:8080/mcp", transport.url
    refute transport.running?
  end

  def test_streamable_http_with_streaming_option
    transport = Ask::MCP::Transport::StreamableHTTP.new(
      "http://localhost:8080/mcp", stream: true, timeout: 60
    )
    assert transport.instance_variable_get(:@options)[:stream]
    assert_equal 60, transport.instance_variable_get(:@options)[:timeout]
  end

  def test_stdio_not_running_before_start
    transport = Ask::MCP::Transport::Stdio.new("echo", ["test"])
    refute transport.running?
  end

  def test_transport_on_message_adds_handler
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    calls = []
    transport.on_message { calls << :called }
    assert transport.instance_variable_get(:@message_handlers).any?
  end
end
