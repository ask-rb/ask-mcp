# frozen_string_literal: true

require_relative "../test_helper"

class SSETransportTest < Minitest::Test
  def test_initialize_with_url
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    assert_equal "http://localhost:8080/sse", transport.url
    refute transport.running?
  end

  def test_initialize_with_options
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse",
      timeout: 60, max_retries: 3,
      headers: { "Authorization" => "Bearer token" },
      reconnect_delay: 2.0, max_reconnect_delay: 60.0
    )
    opts = transport.instance_variable_get(:@options)
    assert_equal 60, opts[:timeout]
    assert_equal 3, transport.instance_variable_get(:@max_retries)
    assert_equal 2.0, transport.instance_variable_get(:@reconnect_delay)
    assert_equal 60.0, transport.instance_variable_get(:@max_reconnect_delay)
  end

  def test_on_message_registers_handler
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    calls = []
    transport.on_message { |msg| calls << msg }
    assert transport.instance_variable_get(:@message_handlers).any?
  end

  def test_stop_without_start
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    transport.stop
    refute transport.running?
  end

  def test_shutdown_aliases_stop
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    transport.shutdown
    refute transport.running?
  end

  def test_calculate_backoff_first_retry
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    delay = transport.__send__(:calculate_backoff)
    assert delay > 0
    assert delay <= 30
  end

  def test_calculate_backoff_with_jitter
    results = 10.times.map { Ask::MCP::Transport::SSE.new("http://localhost:8080/sse").__send__(:calculate_backoff) }
    refute results.uniq.size == 1, "Backoff should include jitter"
  end

  def test_handle_disconnect_not_running
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse", max_retries: 5)
    transport.instance_variable_set(:@running, false)
    transport.__send__(:handle_disconnect, RuntimeError.new("test"))
    assert true
  end

  def test_handle_disconnect_with_retries_exhausted
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse", max_retries: 0)
    transport.instance_variable_set(:@running, false)
    transport.__send__(:handle_disconnect, RuntimeError.new("test"))
    assert true
  end

  def test_process_chunk_empty_line
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    transport.__send__(:process_chunk, "")
    assert true
  end

  def test_process_chunk_endpoint_event
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    transport.__send__(:process_chunk, "event: endpoint\ndata: http://localhost:8080/message\n\n")
    assert_equal "http://localhost:8080/message", transport.instance_variable_get(:@post_url)
  end

  def test_process_chunk_message_event
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    messages = []
    transport.on_message { |msg| messages << msg }
    transport.__send__(:process_chunk, "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n")
    assert messages.any?
  end

  def test_default_max_reconnect_delay
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    assert_equal 30.0, transport.instance_variable_get(:@max_reconnect_delay)
  end

  def test_default_retries
    transport = Ask::MCP::Transport::SSE.new("http://localhost:8080/sse")
    assert_equal 5, transport.instance_variable_get(:@max_retries)
  end
end
