# frozen_string_literal: true

module Ask
  module MCP
    class Resource
      attr_reader :uri, :name, :description, :mime_type

      def initialize(uri:, name:, description: nil, mime_type: nil)
        @uri = uri
        @name = name
        @description = description
        @mime_type = mime_type
      end

      def to_h
        h = { uri: @uri, name: @name }
        h[:description] = @description if @description
        h[:mimeType] = @mime_type if @mime_type
        h
      end

      def self.from_h(hash)
        new(
          uri: hash[:uri] || hash["uri"],
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"],
          mime_type: hash[:mimeType] || hash["mime_type"] || hash[:mime_type]
        )
      end
    end
  end
end
