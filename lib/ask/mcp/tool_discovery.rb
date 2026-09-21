# frozen_string_literal: true

module Ask
  module MCP
    # Helpers for discovering MCP tools and exposing them as Ask::Tool wrappers.
    #
    #   include Ask::MCP::ToolDiscovery
    #   tools = mcp_tools(client)  # => Hash{String => Adapters::AskTool}
    #
    module ToolDiscovery
      # Discover tools from an MCP client and wrap them as AskTool adapters.
      #
      # @param client [Ask::MCP::Client] an initialized MCP client
      # @return [Hash{String => Adapters::AskTool}] tools keyed by name
      def mcp_tools(client)
        tools = client.tools
        Adapters::AskTool.wrap(tools)
      end

      # Discover tools and convert them to Ask::Tools::Tool instances.
      #
      # @param client [Ask::MCP::Client] an initialized MCP client
      # @return [Hash{String => Ask::Tools::Tool}] tools keyed by name
      def mcp_ask_tools(client)
        mcp_tools(client).transform_values(&:to_ask_tool)
      end
    end
  end
end
