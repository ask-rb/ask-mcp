# frozen_string_literal: true

module Ask
  module MCP
    class Server
      attr_reader :name, :version, :capabilities, :tools, :resources, :prompts

      def initialize(name:, version: "0.1.0", capabilities: {}, tools: {}, resources: {}, prompts: {})
        @name = name
        @version = version
        @capabilities = capabilities
        @tools = tools
        @resources = resources
        @prompts = prompts
      end

      def tool_names
        @tools.keys
      end

      def resource_uris
        @resources.keys
      end

      def prompt_names
        @prompts.keys
      end

      def to_h
        {
          name: @name,
          version: @version,
          capabilities: @capabilities,
          tools: @tools.values.map(&:to_h),
          resources: @resources.values.map(&:to_h),
          prompts: @prompts.values.map(&:to_h)
        }
      end
    end
  end
end
