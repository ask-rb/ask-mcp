# frozen_string_literal: true

require_relative "test_helper"

class ToolTest < Minitest::Test
  def test_from_h
    tool = Ask::MCP::Tool.from_h(
      name: "read_file",
      description: "Read a file",
      inputSchema: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"]
      }
    )
    assert_equal "read_file", tool.name
    assert_equal "Read a file", tool.description
    assert_equal "object", tool.input_schema[:type]
  end

  def test_from_h_with_string_keys
    tool = Ask::MCP::Tool.from_h(
      "name" => "write_file",
      "description" => "Write a file",
      "inputSchema" => { "type" => "object" }
    )
    assert_equal "write_file", tool.name
    assert_equal "object", tool.input_schema["type"]
  end

  def test_to_h
    tool = Ask::MCP::Tool.new(
      name: "search",
      description: "Search the web",
      input_schema: { type: "object", properties: { query: { type: "string" } } }
    )
    h = tool.to_h
    assert_equal "search", h[:name]
    assert_equal "Search the web", h[:description]
    assert_equal "object", h[:inputSchema][:type]
  end

  def test_to_ask_tool
    tool = Ask::MCP::Tool.new(name: "test", description: "A test", input_schema: { type: "object" })
    # The adapter method exists even if ask-tools isn't loaded
    assert_respond_to tool, :to_ask_tool
  end
end
