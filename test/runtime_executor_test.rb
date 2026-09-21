# frozen_string_literal: true

require_relative "test_helper"
require "ask/runtime"

class RuntimeExecutorTest < Minitest::Test
  # --- Fake MCP client for unit tests ---

  class FakeClient
    attr_reader :calls, :call_count

    def initialize(&block)
      @handler = block
      @calls = []
      @call_count = 0
    end

    def call_tool(name, arguments = {})
      @calls << [name, arguments]
      @call_count += 1
      @handler.call(name, arguments)
    end

    def tools
      {}
    end
  end

  class FakeErrorClient < FakeClient
    def call_tool(name, arguments = {})
      super
    rescue Ask::MCP::ProtocolError
      raise
    end
  end

  # --- Helpers ---

  def build_tool_call(**overrides)
    Ask::Runtime::ToolCall.new(
      tool_name: "search",
      input: { query: "test" },
      session_id: "s_001",
      turn: 1,
      **overrides
    )
  end

  def build_context(**overrides)
    Ask::Runtime::ExecutionContext.new(
      session_id: "s_001",
      turn: 1,
      caller_id: "test_agent",
      **overrides
    )
  end

  # --- Success cases ---

  def test_execute_success_array_content
    client = FakeClient.new do |_name, _args|
      [{ type: "text", text: "hello" }]
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal "hello", result.output
    assert_equal 1, client.call_count
    assert_equal "search", client.calls.first[0]
    assert_equal({ query: "test" }, client.calls.first[1])
  end

  def test_execute_success_hash_content
    client = FakeClient.new do |_name, _args|
      { content: [{ type: "text", text: "result" }] }
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal "result", result.output
  end

  def test_execute_success_string_response
    client = FakeClient.new do |_name, _args|
      "plain text"
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal "plain text", result.output
  end

  def test_execute_success_nil_response
    client = FakeClient.new do |_name, _args|
      nil
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_nil result.output
  end

  def test_execute_success_multiple_text_items_joined
    client = FakeClient.new do |_name, _args|
      [{ type: "text", text: "line1" }, { type: "text", text: "line2" }]
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal "line1\nline2", result.output
  end

  def test_execute_success_hash_without_content_key
    client = FakeClient.new do |_name, _args|
      { rows: [1, 2, 3], count: 3 }
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal({ rows: [1, 2, 3], count: 3 }, result.output)
  end

  # --- MCP error cases ---

  def test_execute_failure_is_error_flag
    client = FakeClient.new do |_name, _args|
      { content: [{ type: "text", text: "not found" }], isError: true }
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.failure?
    assert_equal "not found", result.error_message
  end

  def test_execute_failure_protocol_error
    client = FakeClient.new do |_name, _args|
      raise Ask::MCP::ProtocolError, "tool not found"
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.failure?
    assert_equal "tool not found", result.error_message
  end

  def test_execute_failure_connection_error
    client = FakeClient.new do |_name, _args|
      raise Ask::MCP::ConnectionError, "not connected"
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.failure?
    assert_equal "not connected", result.error_message
  end

  def test_execute_failure_generic_error
    client = FakeClient.new do |_name, _args|
      raise RuntimeError, "something broke"
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.failure?
    assert_equal "RuntimeError: something broke", result.error_message
  end

  def test_execute_failure_is_error_without_content
    client = FakeClient.new do |_name, _args|
      { isError: true }
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.failure?
    assert_equal "MCP tool error", result.error_message
  end

  # --- Cancellation cases ---

  def test_execute_cancelled_before_call
    canceller = Ask::Runtime::Canceller.new
    canceller.cancel
    context = build_context(canceller: canceller)

    client = FakeClient.new do |_name, _args|
      flunk "should not be called"
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call, context: context)

    assert result.cancelled?
    assert_equal 0, client.call_count
  end

  def test_execute_cancelled_during_call
    call_count = 0
    client = FakeClient.new do |_name, _args|
      call_count += 1
      [{ type: "text", text: "ok" }]
    end

    canceller = Ask::Runtime::Canceller.new
    context = build_context(canceller: canceller)

    executor = Ask::MCP::RuntimeExecutor.new(client)
    # Cancel after the first call_tool invocation
    canceller.on_cancel { }
    canceller.cancel

    result = executor.execute(build_tool_call, context: context)
    assert result.cancelled?
  end

  def test_execute_cancelled_after_success_does_not_override
    client = FakeClient.new do |_name, _args|
      [{ type: "text", text: "ok" }]
    end

    canceller = Ask::Runtime::Canceller.new
    context = build_context(canceller: canceller)

    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call, context: context)

    assert result.success?
    assert_equal "ok", result.output
  end

  # --- Correlation metadata ---

  def test_preserves_tool_call_id_and_session
    client = FakeClient.new do |_name, _args|
      [{ type: "text", text: "ok" }]
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)

    call = build_tool_call(id: "tc_custom", session_id: "s_99", turn: 5)
    context = build_context(session_id: "s_99", turn: 5)
    executor.execute(call, context: context)

    assert_equal "tc_custom", call.id
    assert_equal "s_99", call.session_id
    assert_equal 5, call.turn
  end

  def test_preserves_input_data
    client = FakeClient.new do |_name, args|
      assert_equal({ path: "/tmp/file" }, args)
      [{ type: "text", text: "content" }]
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)

    call = build_tool_call(input: { path: "/tmp/file" })
    result = executor.execute(call)
    assert result.success?
  end

  # --- Event ordering ---

  def test_events_emitted_in_order
    events = []
    sink = Ask::Runtime::EventSink.new
    sink.on(:tool_started) { |payload| events << [:started, payload[:event]] }
    sink.on(:tool_completed) { |payload| events << [:completed, payload[:event]] }

    client = FakeClient.new do |_name, _args|
      [{ type: "text", text: "ok" }]
    end
    context = build_context(event_sink: sink)
    executor = Ask::MCP::RuntimeExecutor.new(client)
    executor.execute(build_tool_call, context: context)

    assert_equal 2, events.size
    assert_equal :started, events[0][0]
    assert_equal :completed, events[1][0]
    assert_kind_of Ask::Runtime::Events::ToolStarted, events[0][1]
    assert_kind_of Ask::Runtime::Events::ToolCompleted, events[1][1]
  end

  def test_failure_events_emitted
    events = []
    sink = Ask::Runtime::EventSink.new
    sink.on(:tool_started) { |payload| events << [:started, payload[:event]] }
    sink.on(:tool_failed) { |payload| events << [:failed, payload[:event]] }

    client = FakeClient.new do |_name, _args|
      raise Ask::MCP::ProtocolError, "boom"
    end
    context = build_context(event_sink: sink)
    executor = Ask::MCP::RuntimeExecutor.new(client)
    executor.execute(build_tool_call, context: context)

    assert_equal 2, events.size
    assert_equal :started, events[0][0]
    assert_equal :failed, events[1][0]
    assert_kind_of Ask::Runtime::Events::ToolFailed, events[1][1]
  end

  def test_cancelled_events_emitted
    events = []
    sink = Ask::Runtime::EventSink.new
    sink.on(:tool_started) { |payload| events << [:started, payload[:event]] }
    sink.on(:tool_cancelled) { |payload| events << [:cancelled, payload[:event]] }

    canceller = Ask::Runtime::Canceller.new
    canceller.cancel
    context = build_context(canceller: canceller, event_sink: sink)

    client = FakeClient.new { flunk }
    executor = Ask::MCP::RuntimeExecutor.new(client)
    executor.execute(build_tool_call, context: context)

    assert_equal 2, events.size
    assert_equal :started, events[0][0]
    assert_equal :cancelled, events[1][0]
    assert_kind_of Ask::Runtime::Events::ToolCancelled, events[1][1]
  end

  def test_event_tool_name_matches_call
    captured_event = nil
    sink = Ask::Runtime::EventSink.new
    sink.on(:tool_completed) { |payload| captured_event = payload[:event] }

    client = FakeClient.new { [{ type: "text", text: "ok" }] }
    context = build_context(event_sink: sink)
    executor = Ask::MCP::RuntimeExecutor.new(client)

    call = build_tool_call(id: "tc_evt", tool_name: "weather")
    executor.execute(call, context: context)

    assert_equal "weather", captured_event.tool_name
    assert_equal "tc_evt", captured_event.tool_call_id
  end

  # --- Malformed results ---

  def test_execute_malformed_integer_response
    client = FakeClient.new do |_name, _args|
      42
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal "42", result.output
  end

  def test_execute_malformed_empty_array
    client = FakeClient.new do |_name, _args|
      []
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_nil result.output
  end

  def test_execute_malformed_hash_with_non_text_content
    client = FakeClient.new do |_name, _args|
      [{ type: "image", data: "base64data" }]
    end
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal [{ type: "image", data: "base64data" }], result.output
  end

  # --- Interface compliance ---

  def test_includes_tool_executor_module
    executor = Ask::MCP::RuntimeExecutor.new(FakeClient.new { nil })
    assert executor.is_a?(Ask::Runtime::ToolExecutor)
  end

  def test_client_accessor
    fake = FakeClient.new { nil }
    executor = Ask::MCP::RuntimeExecutor.new(fake)
    assert_same fake, executor.client
  end

  def test_factory_method
    fake = FakeClient.new { nil }
    executor = Ask::MCP::RuntimeExecutor.from_client(fake)
    assert_instance_of Ask::MCP::RuntimeExecutor, executor
    assert_same fake, executor.client
  end

  def test_execute_with_nil_context
    client = FakeClient.new { [{ type: "text", text: "ok" }] }
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.success?
    assert_equal "ok", result.output
  end

  # --- ToolDiscovery ---

  def test_tool_discovery_include
    klass = Class.new do
      include Ask::MCP::ToolDiscovery
    end
    obj = klass.new
    assert obj.respond_to?(:mcp_tools)
    assert obj.respond_to?(:mcp_ask_tools)
  end

  # --- Duration tracking ---

  def test_result_has_duration
    client = FakeClient.new { [{ type: "text", text: "ok" }] }
    executor = Ask::MCP::RuntimeExecutor.new(client)
    result = executor.execute(build_tool_call)

    assert result.duration.is_a?(Numeric)
    assert result.duration >= 0
  end
end
