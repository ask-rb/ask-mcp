# frozen_string_literal: true

module Ask
  module MCP
    class Tool
      attr_reader :name, :description, :input_schema, :title, :icons

      def initialize(name:, description: "", input_schema: {}, title: nil, icons: [])
        @name = name
        @description = description
        @input_schema = input_schema
        @title = title
        @icons = icons
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
        h = {
          name: @name,
          description: @description,
          inputSchema: @input_schema
        }
        h[:title] = @title if @title
        h[:icons] = @icons if @icons.any?
        h
      end

      def self.from_h(hash)
        new(
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"] || "",
          input_schema: hash[:inputSchema] || hash["input_schema"] || hash[:input_schema] || hash["inputSchema"] || {},
          title: hash[:title] || hash["title"],
          icons: hash[:icons] || hash["icons"] || []
        )
      end
    end
  end
end
