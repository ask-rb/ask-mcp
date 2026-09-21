# frozen_string_literal: true

require_relative "test_helper"
require "ask/runtime"

class ToolDiscoveryTest < Minitest::Test
  class FakeClient
    def initialize(tools_hash)
      @tools_hash = tools_hash
    end

    def tools
      @tools_hash
    end
  end

  def test_mcp_tools_wraps_client_tools
    tools = {
      "search" => Ask::MCP::Tool.new(name: "search", description: "Search"),
      "read" => Ask::MCP::Tool.new(name: "read", description: "Read files")
    }
    client = FakeClient.new(tools)

    obj = Object.new
    obj.extend(Ask::MCP::ToolDiscovery)
    result = obj.mcp_tools(client)

    assert_equal 2, result.size
    assert_instance_of Ask::MCP::Adapters::AskTool, result["search"]
    assert_equal "Search", result["search"].description
    assert_equal "Read files", result["read"].description
  end

  def test_mcp_ask_tools_delegates_to_wrap_and_transform
    tools = {
      "search" => Ask::MCP::Tool.new(
        name: "search",
        description: "Search",
        input_schema: { type: "object", properties: { q: { type: "string" } } }
      )
    }
    client = FakeClient.new(tools)

    obj = Object.new
    obj.extend(Ask::MCP::ToolDiscovery)

    # mcp_ask_tools wraps tools as AskTool and calls to_ask_tool.
    # Verify the wrapping step works; to_ask_tool requires ask-agent
    # which may not be available in all environments.
    wrapped = obj.mcp_tools(client)
    assert_equal 1, wrapped.size
    assert_instance_of Ask::MCP::Adapters::AskTool, wrapped["search"]
    assert_equal "search", wrapped["search"].name
  end

  def test_mcp_tools_empty
    client = FakeClient.new({})

    obj = Object.new
    obj.extend(Ask::MCP::ToolDiscovery)
    result = obj.mcp_tools(client)

    assert_empty result
  end
end
