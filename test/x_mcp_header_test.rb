# frozen_string_literal: true

require_relative "test_helper"

class XMcpHeaderTest < Minitest::Test
  def reason(schema)
    Ask::MCP::XMcpHeader.invalid_reason(schema)
  end

  def test_no_annotations_is_valid
    assert_nil reason({ type: "object", properties: { a: { type: "string" } } })
  end

  def test_valid_annotation
    schema = {
      type: "object",
      properties: { region: { type: "string", :'x-mcp-header' => "Region" } }
    }
    assert_nil reason(schema)
  end

  def test_valid_annotation_with_string_keys
    schema = {
      "type" => "object",
      "properties" => { "region" => { "type" => "string", "x-mcp-header" => "Region" } }
    }
    assert_nil reason(schema)
  end

  def test_empty_header_name_is_invalid
    schema = {
      type: "object",
      properties: { a: { type: "string", :'x-mcp-header' => "" } }
    }
    assert_match(/empty/, reason(schema))
  end

  def test_invalid_characters_are_invalid
    schema = {
      type: "object",
      properties: { a: { type: "string", :'x-mcp-header' => "Bad Header" } }
    }
    assert_match(/invalid characters/, reason(schema))
  end

  def test_non_primitive_type_is_invalid
    schema = {
      type: "object",
      properties: { a: { type: "number", :'x-mcp-header' => "Num" } }
    }
    assert_match(/primitive/, reason(schema))

    object_schema = {
      type: "object",
      properties: { a: { type: "object", :'x-mcp-header' => "Obj" } }
    }
    assert_match(/primitive/, reason(object_schema))
  end

  def test_missing_type_is_invalid
    schema = {
      type: "object",
      properties: { a: { :'x-mcp-header' => "X" } }
    }
    assert_match(/primitive/, reason(schema))
  end

  def test_case_insensitive_duplicate_is_invalid
    schema = {
      type: "object",
      properties: {
        a: { type: "string", :'x-mcp-header' => "Region" },
        b: { type: "string", :'x-mcp-header' => "region" }
      }
    }
    assert_match(/duplicate/i, reason(schema))
  end

  def test_annotation_under_one_of_is_invalid
    schema = {
      type: "object",
      properties: {
        a: {
          oneOf: [
            { type: "string", :'x-mcp-header' => "A" },
            { type: "integer" }
          ]
        }
      }
    }
    assert_match(/non-properties keywords/, reason(schema))
  end

  def test_annotation_under_items_is_invalid
    schema = {
      type: "object",
      properties: {
        a: {
          type: "array",
          items: { type: "string", :'x-mcp-header' => "A" }
        }
      }
    }
    assert_match(/non-properties keywords/, reason(schema))
  end

  def test_annotation_under_ref_is_invalid
    schema = {
      type: "object",
      properties: {
        a: { :'$ref' => "#/$defs/inner" }
      },
      :'$defs' => {
        inner: { type: "string", :'x-mcp-header' => "A" }
      }
    }
    assert_match(/non-properties keywords/, reason(schema))
  end

  def test_nested_object_via_properties_is_valid
    schema = {
      type: "object",
      properties: {
        headers: {
          type: "object",
          properties: {
            region: { type: "string", :'x-mcp-header' => "Region" }
          }
        }
      }
    }
    assert_nil reason(schema)
  end

  def test_integer_and_boolean_types_are_valid
    schema = {
      type: "object",
      properties: {
        a: { type: "integer", :'x-mcp-header' => "A" },
        b: { type: "boolean", :'x-mcp-header' => "B" }
      }
    }
    assert_nil reason(schema)
  end

  def test_safe_integer_range
    assert Ask::MCP::XMcpHeader.safe_integer?(0)
    assert Ask::MCP::XMcpHeader.safe_integer?(2**53 - 1)
    assert Ask::MCP::XMcpHeader.safe_integer?(-(2**53) + 1)
    refute Ask::MCP::XMcpHeader.safe_integer?(2**53)
    refute Ask::MCP::XMcpHeader.safe_integer?(-(2**53))
    refute Ask::MCP::XMcpHeader.safe_integer?("42")
  end
end
