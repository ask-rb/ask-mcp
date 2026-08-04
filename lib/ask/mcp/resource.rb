# frozen_string_literal: true

module Ask
  module MCP
    class Resource
      attr_reader :uri, :name, :description, :mime_type, :title, :icons

      def initialize(uri:, name:, description: nil, mime_type: nil, title: nil, icons: [])
        @uri = uri
        @name = name
        @description = description
        @mime_type = mime_type
        @title = title
        @icons = icons
      end

      def to_h
        h = { uri: @uri, name: @name }
        h[:title] = @title if @title
        h[:description] = @description if @description
        h[:mimeType] = @mime_type if @mime_type
        h[:icons] = @icons if @icons.any?
        h
      end

      def self.from_h(hash)
        new(
          uri: hash[:uri] || hash["uri"],
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"],
          mime_type: hash[:mimeType] || hash["mime_type"] || hash[:mime_type],
          title: hash[:title] || hash["title"],
          icons: hash[:icons] || hash["icons"] || []
        )
      end
    end
  end
end
