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

  def test_from_h_with_input_schema_string_key
    tool = Ask::MCP::Tool.from_h(
      "name" => "test",
      "input_schema" => { type: "object" }
    )
    assert_equal "test", tool.name
    assert_equal "object", tool.input_schema[:type]
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
    assert_respond_to tool, :to_ask_tool
  end

  def test_default_description
    tool = Ask::MCP::Tool.new(name: "no_desc")
    assert_equal "", tool.description
    assert_equal({}, tool.input_schema)
  end

  def test_minimal_input_schema
    tool = Ask::MCP::Tool.new(name: "minimal", input_schema: {})
    assert_equal({}, tool.input_schema)
  end

  def test_from_h_parses_title_and_icons
    tool = Ask::MCP::Tool.from_h(
      name: "weather",
      title: "Weather",
      description: "Weather lookup",
      inputSchema: { type: "object" },
      icons: [{ src: "https://example.com/icon.png", mimeType: "image/png", sizes: ["48x48"] }]
    )
    assert_equal "Weather", tool.title
    assert_equal "https://example.com/icon.png", tool.icons.first[:src]
  end

  def test_from_h_parses_title_and_icons_with_string_keys
    tool = Ask::MCP::Tool.from_h(
      "name" => "weather",
      "title" => "Weather",
      "icons" => [{ "src" => "https://example.com/icon.png" }]
    )
    assert_equal "Weather", tool.title
    # Icon entries are passed through verbatim (same as Prompt#arguments), so
    # their keys keep the original style — string here, symbol on the wire
    # (the parser symbolizes JSON keys).
    assert_equal "https://example.com/icon.png", tool.icons.first["src"]
  end

  def test_to_h_includes_title_and_icons_when_present
    tool = Ask::MCP::Tool.new(
      name: "weather",
      title: "Weather",
      icons: [{ src: "https://example.com/icon.png", sizes: ["48x48"] }]
    )
    h = tool.to_h
    assert_equal "Weather", h[:title]
    assert_equal "https://example.com/icon.png", h[:icons].first[:src]
  end

  def test_to_h_omits_title_and_icons_when_absent
    tool = Ask::MCP::Tool.new(name: "plain")
    h = tool.to_h
    refute h.key?(:title)
    refute h.key?(:icons)
  end

  def test_default_title_and_icons
    tool = Ask::MCP::Tool.new(name: "plain")
    assert_nil tool.title
    assert_equal [], tool.icons
  end

  def test_equality
    t1 = Ask::MCP::Tool.new(name: "test", description: "desc", input_schema: { type: "object" })
    t2 = Ask::MCP::Tool.new(name: "test", description: "desc", input_schema: { type: "object" })
    assert_equal t1.name, t2.name
    assert_equal t1.description, t2.description
  end
end
