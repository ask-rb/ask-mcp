# frozen_string_literal: true

require_relative "../test_helper"

class ToolServerTest < Minitest::Test
  # Test helpers — simple objects that quack like Ask::Tool and Ask::Result

  class EchoTool
    def name; "echo" end
    def description; "Echo back a message" end
    def params_schema
      { type: "object", properties: { "message" => { "type" => "string" } }, "required" => ["message"] }
    end
    def call(args = {})
      OpenStruct.new(ok?: true, output: "Echo: #{args['message']}", error_message: nil, ok: true)
    end
  end

  class ErrorTool
    def name; "fail" end
    def description; "Always fails" end
    def params_schema; nil end
    def call(args = {})
      OpenStruct.new(ok?: false, output: nil, error_message: "something broke", ok: false)
    end
  end

  class NoopTool
    def name; "noop" end
    def description; nil end
    def params_schema; nil end
    def call(args = {})
      OpenStruct.new(ok?: true, output: "", error_message: nil, ok: true)
    end
  end

  def setup
    @adapter = Ask::MCP::Adapters::ToolServer.new([EchoTool.new, ErrorTool.new, NoopTool.new])
  end

  # --- definitions ---

  def test_definitions_includes_all_tools
    defs = @adapter.definitions
    assert_equal 3, defs.length
    names = defs.map { |d| d[:name] }
    assert_includes names, "echo"
    assert_includes names, "fail"
    assert_includes names, "noop"
  end

  def test_definition_has_name_description_input_schema
    defn = @adapter.definitions.find { |d| d[:name] == "echo" }
    assert_equal "echo", defn[:name]
    assert_equal "Echo back a message", defn[:description]
    assert_equal "object", defn[:inputSchema][:type]
    assert defn[:inputSchema][:properties].key?("message") || defn[:inputSchema][:properties].key?(:message),
           "echo should have message param"
  end

  def test_definition_description_falls_back_to_empty_string
    defn = @adapter.definitions.find { |d| d[:name] == "noop" }
    assert_equal "", defn[:description]
  end

  def test_definition_input_schema_falls_back_when_nil
    defn = @adapter.definitions.find { |d| d[:name] == "noop" }
    assert_equal "object", defn[:inputSchema][:type]
    assert_equal({}, defn[:inputSchema][:properties])
    assert_equal [], defn[:inputSchema][:required]
  end

  # --- calling ---

  def test_call_dispatches_to_correct_tool
    result = @adapter.call("echo", { "message" => "hello" })
    assert_equal false, result[:isError]
    text = result[:content].first[:text]
    assert_equal "Echo: hello", text
  end

  def test_call_unknown_tool_returns_error
    result = @adapter.call("nonexistent", {})
    assert_equal true, result[:isError]
    assert_match(/Tool not found/, result[:content].first[:text])
  end

  def test_call_error_tool_sets_iserror
    result = @adapter.call("fail", {})
    assert_equal true, result[:isError]
    assert_match(/something broke/, result[:content].first[:text])
  end

  # Test that a tool which raises an exception (not Ask::Tool::Halt) returns an error
  def test_call_tool_that_raises_exception_returns_error
    tool = Class.new do
      def name; "boom" end
      def description; "" end
      def params_schema; nil end
      def call(args = {}); raise RuntimeError, "kaboom" end
    end
    adapter = Ask::MCP::Adapters::ToolServer.new([tool.new])
    result = adapter.call("boom", {})
    assert_equal true, result[:isError]
    assert_match(/RuntimeError/, result[:content].first[:text])
  end

  # Test that a tool which returns a success result with halt-like behavior handles cleanly
  def test_tool_that_halts_returns_success
    tool = Class.new do
      def name; "halter" end
      def description; "" end
      def params_schema; nil end
      def call(args = {})
        OpenStruct.new(ok?: true, output: "stopped", error_message: nil, ok: true)
      end
    end
    adapter = Ask::MCP::Adapters::ToolServer.new([tool.new])
    result = adapter.call("halter", {})
    assert_equal false, result[:isError], "Halt-style result should succeed"
    assert_equal "stopped", result[:content].first[:text]
  end

  def test_call_with_hash_output_extracts_summary
    tool = Class.new do
      def name; "hashy" end
      def description; "" end
      def params_schema; nil end
      def call(args = {})
        OpenStruct.new(ok?: true, output: { summary: "done", detail: "stuff" }, error_message: nil, ok: true)
      end
    end
    adapter = Ask::MCP::Adapters::ToolServer.new([tool.new])
    result = adapter.call("hashy", {})
    assert_equal "done", result[:content].first[:text]
  end

  def test_call_with_hash_output_no_summary_uses_to_s
    tool = Class.new do
      def name; "raw" end
      def description; "" end
      def params_schema; nil end
      def call(args = {})
        OpenStruct.new(ok?: true, output: { raw: "data" }, error_message: nil, ok: true)
      end
    end
    adapter = Ask::MCP::Adapters::ToolServer.new([tool.new])
    result = adapter.call("raw", {})
    assert result[:content].first[:text].include?("data")
  end

  def test_arguments_are_stringified
    tool = Class.new do
      attr_reader :received_args
      def name; "capture" end
      def description; "" end
      def params_schema; nil end
      def call(args = {})
        @received_args = args
        OpenStruct.new(ok?: true, output: "ok", error_message: nil, ok: true)
      end
    end
    instance = tool.new
    adapter = Ask::MCP::Adapters::ToolServer.new([instance])
    adapter.call("capture", { "key" => "value", "nested" => { "inner" => 1 } })
    assert_equal "value", instance.received_args["key"]
    assert_equal 1, instance.received_args["nested"]["inner"]
  end
end
