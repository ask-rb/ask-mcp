# frozen_string_literal: true

module Ask
  module MCP
    class Prompt
      attr_reader :name, :description, :arguments, :title, :icons

      def initialize(name:, description: nil, arguments: [], title: nil, icons: [])
        @name = name
        @description = description
        @arguments = arguments
        @title = title
        @icons = icons
      end

      def to_h
        h = { name: @name }
        h[:title] = @title if @title
        h[:description] = @description if @description
        h[:arguments] = @arguments if @arguments.any?
        h[:icons] = @icons if @icons.any?
        h
      end

      def self.from_h(hash)
        new(
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"],
          arguments: hash[:arguments] || hash["arguments"] || [],
          title: hash[:title] || hash["title"],
          icons: hash[:icons] || hash["icons"] || []
        )
      end
    end
  end
end
