# frozen_string_literal: true

module Ask
  module MCP
    module Adapters
      class AskTool
        def initialize(mcp_tool)
          @mcp_tool = mcp_tool
        end

        def name
          @mcp_tool.name
        end

        def description
          @mcp_tool.description
        end

        def parameters
          @mcp_tool.input_schema
        end

        def to_ask_tool
          require "ask/tools/tool"

          Ask::Tools::Tool.new(
            name: @mcp_tool.name,
            description: @mcp_tool.description,
            parameters: @mcp_tool.input_schema
          )
        end

        def self.from(mcp_tool)
          new(mcp_tool)
        end

        def self.wrap(tools_hash)
          tools_hash.transform_values { |tool| new(tool) }
        end
      end
    end
  end
end
