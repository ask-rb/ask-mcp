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
end
