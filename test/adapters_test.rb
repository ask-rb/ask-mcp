# frozen_string_literal: true

require_relative "test_helper"

class AdaptersTest < Minitest::Test
  def test_ask_tool_adapter_create
    mcp_tool = Ask::MCP::Tool.new(
      name: "read_file",
      description: "Read files",
      input_schema: { type: "object", properties: { path: { type: "string" } } }
    )
    adapter = Ask::MCP::Adapters::AskTool.new(mcp_tool)
    assert_equal "read_file", adapter.name
    assert_equal "Read files", adapter.description
    assert_equal({ type: "object", properties: { path: { type: "string" } } }, adapter.parameters)
  end

  def test_ask_tool_adapter_from
    mcp_tool = Ask::MCP::Tool.new(name: "test", description: "Test")
    adapter = Ask::MCP::Adapters::AskTool.from(mcp_tool)
    assert_instance_of Ask::MCP::Adapters::AskTool, adapter
  end

  def test_ask_tool_adapter_wrap
    tools = {
      "a" => Ask::MCP::Tool.new(name: "a", description: "Tool A"),
      "b" => Ask::MCP::Tool.new(name: "b", description: "Tool B")
    }
    wrapped = Ask::MCP::Adapters::AskTool.wrap(tools)
    assert_equal 2, wrapped.size
    assert_instance_of Ask::MCP::Adapters::AskTool, wrapped["a"]
    assert_equal "Tool A", wrapped["a"].description
  end

  # --- ToolServer definitions: optional title/icons pass-through ---

  class DuckToolWithMetadata
    def name = "weather"
    def description = "Weather lookup"
    def params_schema = { type: "object", properties: {}, required: [] }
    def title = "Weather"
    def icons = [{ src: "https://example.com/icon.png", mimeType: "image/png" }]
    def call(args) = "sunny"
  end

  class DuckToolPlain
    def name = "plain"
    def description = "Plain tool"
    def params_schema = { type: "object" }
    def call(args) = "ok"
  end

  def test_tool_server_definitions_include_title_and_icons_when_provided
    adapter = Ask::MCP::Adapters::ToolServer.new([DuckToolWithMetadata.new])
    defn = adapter.definitions.first
    assert_equal "weather", defn[:name]
    assert_equal "Weather", defn[:title]
    assert_equal "https://example.com/icon.png", defn[:icons].first[:src]
  end

  def test_tool_server_definitions_omit_title_and_icons_when_absent
    adapter = Ask::MCP::Adapters::ToolServer.new([DuckToolPlain.new])
    defn = adapter.definitions.first
    refute defn.key?(:title)
    refute defn.key?(:icons)
  end
end
