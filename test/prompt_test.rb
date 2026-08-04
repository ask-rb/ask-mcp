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

  def test_from_h_parses_title_and_icons
    prompt = Ask::MCP::Prompt.from_h(
      name: "greet",
      title: "Greet",
      icons: [{ src: "https://example.com/icon.png" }]
    )
    assert_equal "Greet", prompt.title
    assert_equal "https://example.com/icon.png", prompt.icons.first[:src]
  end

  def test_to_h_includes_title_and_icons_when_present
    prompt = Ask::MCP::Prompt.new(
      name: "greet",
      title: "Greet",
      icons: [{ src: "https://example.com/icon.png" }]
    )
    h = prompt.to_h
    assert_equal "Greet", h[:title]
    assert_equal "https://example.com/icon.png", h[:icons].first[:src]
  end

  def test_to_h_omits_title_and_icons_when_absent
    prompt = Ask::MCP::Prompt.new(name: "simple")
    h = prompt.to_h
    refute h.key?(:title)
    refute h.key?(:icons)
  end
end
