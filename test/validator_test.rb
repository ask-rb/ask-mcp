# frozen_string_literal: true

require_relative "test_helper"

class ValidatorTest < Minitest::Test
  def setup
    @schema = {
      type: "object",
      properties: {
        message: { type: "string", description: "Message to echo" }
      },
      required: ["message"]
    }
    @validator = Ask::MCP::Validator.new(@schema)
  end

  def test_valid_arguments
    assert @validator.valid?({ message: "hello" })
  end

  def test_invalid_arguments_missing_required
    refute @validator.valid?({})
  end

  def test_invalid_arguments_wrong_type
    refute @validator.valid?({ message: 42 })
  end

  def test_valid_without_schema
    validator = Ask::MCP::Validator.new(nil)
    assert validator.valid?({ anything: "goes" })
  end

  def test_valid_with_empty_schema
    validator = Ask::MCP::Validator.new({})
    assert validator.valid?({ anything: "goes" })
  end

  def test_validate_bang_raises_on_invalid
    assert_raises(Ask::MCP::Validator::ValidationError) do
      @validator.validate!({})
    end
  end

  def test_validate_bang_returns_true
    assert @validator.validate!(message: "hello")
  end

  def test_validator_class_method
    assert Ask::MCP.validate!({ type: "object" }, { foo: "bar" })
  end

  def test_nested_schema
    schema = {
      type: "object",
      properties: {
        person: {
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" }
          },
          required: ["name"]
        }
      },
      required: ["person"]
    }
    validator = Ask::MCP::Validator.new(schema)

    assert validator.valid?({ person: { name: "Alice", age: 30 } })
    refute validator.valid?({ person: { age: 30 } })
    refute validator.valid?({})
  end

  def test_array_arguments
    schema = {
      type: "object",
      properties: {
        items: {
          type: "array",
          items: { type: "string" }
        }
      }
    }
    validator = Ask::MCP::Validator.new(schema)
    assert validator.valid?({ items: ["a", "b"] })
    refute validator.valid?({ items: [1, 2] })
  end

  # --- 2025-11-25: JSON Schema 2020-12 default dialect ---

  def test_schema_declaring_2020_12_dialect_validates
    schema = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"]
    }
    validator = Ask::MCP::Validator.new(schema)
    assert validator.valid?({ message: "hello" })
    refute validator.valid?({})
    refute validator.valid?({ message: 42 })
  end

  def test_2020_12_const_keyword_enforced
    schema = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      type: "object",
      properties: { mode: { const: "fast" } }
    }
    validator = Ask::MCP::Validator.new(schema)
    assert validator.valid?({ mode: "fast" })
    refute validator.valid?({ mode: "slow" })
  end

  def test_2020_12_dialect_with_string_keys
    schema = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "type" => "object",
      "properties" => { "count" => { "type" => "integer" } },
      "required" => ["count"]
    }
    validator = Ask::MCP::Validator.new(schema)
    assert validator.valid?({ "count" => 3 })
    refute validator.valid?({ "count" => "three" })
  end

  def test_non_2020_12_schema_errors_still_raise
    # A schema whose metaschema the gem cannot resolve and that does NOT claim
    # the 2020-12 dialect must not be silently re-interpreted.
    schema = {
      "$schema" => "https://example.com/unknown-metaschema",
      type: "object"
    }
    validator = Ask::MCP::Validator.new(schema)
    assert_raises(StandardError) { validator.validate!({}) }
  end
end
