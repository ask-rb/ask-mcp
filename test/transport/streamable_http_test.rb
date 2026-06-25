# frozen_string_literal: true

require_relative "../test_helper"

class StreamableHTTPTransportTest < Minitest::Test
  def test_initialize_with_url
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    assert_equal "http://localhost:8080/mcp", transport.url
    refute transport.running?
  end

  def test_initialize_with_options
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp",
      stream: true, timeout: 60, headers: { "X-Custom" => "value" })
    opts = transport.instance_variable_get(:@options)
    assert opts[:stream]
    assert_equal 60, opts[:timeout]
    assert_equal "value", opts[:headers]["X-Custom"]
  end

  def test_on_message_registers_handler
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    calls = []
    transport.on_message { |msg| calls << msg }
    assert transport.instance_variable_get(:@message_handlers).any?
  end

  def test_stop_without_start
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.stop
    refute transport.running?
  end

  def test_shutdown_aliases_stop
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.shutdown
    refute transport.running?
  end

  def test_start_sets_running
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.start
    assert transport.running?
    transport.stop
  end
end
