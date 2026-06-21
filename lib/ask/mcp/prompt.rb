# frozen_string_literal: true

module Ask
  module MCP
    class Prompt
      attr_reader :name, :description, :arguments

      def initialize(name:, description: nil, arguments: [])
        @name = name
        @description = description
        @arguments = arguments
      end

      def to_h
        h = { name: @name }
        h[:description] = @description if @description
        h[:arguments] = @arguments if @arguments.any?
        h
      end

      def self.from_h(hash)
        new(
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"],
          arguments: hash[:arguments] || hash["arguments"] || []
        )
      end
    end
  end
end
