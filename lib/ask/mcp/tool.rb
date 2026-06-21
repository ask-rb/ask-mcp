# frozen_string_literal: true

module Ask
  module MCP
    class Tool
      attr_reader :name, :description, :input_schema

      def initialize(name:, description: "", input_schema: {})
        @name = name
        @description = description
        @input_schema = input_schema
      end

      def to_ask_tool
        require "ask/tools/tool"

        Ask::Tools::Tool.new(
          name: @name,
          description: @description,
          parameters: @input_schema
        )
      end

      def to_h
        {
          name: @name,
          description: @description,
          inputSchema: @input_schema
        }
      end

      def self.from_h(hash)
        new(
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"] || "",
          input_schema: hash[:inputSchema] || hash["input_schema"] || hash[:input_schema] || hash["inputSchema"] || {}
        )
      end
    end
  end
end
