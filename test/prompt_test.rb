# frozen_string_literal: true

require_relative "test_helper"

class PromptTest < Minitest::Test
  def test_from_h
    prompt = Ask::MCP::Prompt.from_h(
      name: "greet",
      description: "Greet someone",
      arguments: [{ name: "name", description: "The name to greet" }]
    )
    assert_equal "greet", prompt.name
    assert_equal "Greet someone", prompt.description
    assert_equal 1, prompt.arguments.size
    assert_equal "name", prompt.arguments.first[:name]
  end

  def test_to_h
    prompt = Ask::MCP::Prompt.new(name: "test", description: "A test")
    h = prompt.to_h
    assert_equal "test", h[:name]
    assert_equal "A test", h[:description]
    refute h.key?(:arguments)
  end

  def test_minimal_prompt
    prompt = Ask::MCP::Prompt.new(name: "simple")
    h = prompt.to_h
    assert_equal "simple", h[:name]
  end
end
