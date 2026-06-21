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
end
