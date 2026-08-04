# frozen_string_literal: true

require_relative "test_helper"

class ResourceTest < Minitest::Test
  def test_from_h
    resource = Ask::MCP::Resource.from_h(
      uri: "file:///tmp/test.txt",
      name: "Test File",
      description: "A test file",
      mimeType: "text/plain"
    )
    assert_equal "file:///tmp/test.txt", resource.uri
    assert_equal "Test File", resource.name
    assert_equal "A test file", resource.description
    assert_equal "text/plain", resource.mime_type
  end

  def test_to_h
    resource = Ask::MCP::Resource.new(
      uri: "file:///tmp/test.txt",
      name: "Test File",
      mime_type: "text/plain"
    )
    h = resource.to_h
    assert_equal "file:///tmp/test.txt", h[:uri]
    assert_equal "text/plain", h[:mimeType]
  end

  def test_minimal_resource
    resource = Ask::MCP::Resource.new(uri: "file:///dev/null", name: "Null")
    h = resource.to_h
    assert_equal "file:///dev/null", h[:uri]
    assert_equal "Null", h[:name]
    refute h.key?(:mimeType)
  end

  def test_from_h_parses_title_and_icons
    resource = Ask::MCP::Resource.from_h(
      uri: "file:///README.md",
      name: "README.md",
      title: "Project Documentation",
      icons: [{ src: "https://example.com/icon.png", mimeType: "image/png" }]
    )
    assert_equal "Project Documentation", resource.title
    assert_equal "https://example.com/icon.png", resource.icons.first[:src]
  end

  def test_to_h_includes_title_and_icons_when_present
    resource = Ask::MCP::Resource.new(
      uri: "file:///README.md",
      name: "README.md",
      title: "Project Documentation",
      icons: [{ src: "https://example.com/icon.png" }]
    )
    h = resource.to_h
    assert_equal "Project Documentation", h[:title]
    assert_equal "https://example.com/icon.png", h[:icons].first[:src]
  end

  def test_to_h_omits_title_and_icons_when_absent
    resource = Ask::MCP::Resource.new(uri: "file:///dev/null", name: "Null")
    h = resource.to_h
    refute h.key?(:title)
    refute h.key?(:icons)
  end
end
