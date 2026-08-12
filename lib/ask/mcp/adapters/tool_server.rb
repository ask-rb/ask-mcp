# frozen_string_literal: true

require "json"

module Ask
  module MCP
    module Adapters
      # Converts duck-typed tool objects into MCP tool definitions and dispatches
      # calls. This is the server-direction adapter — it takes any objects that
      # respond to +name+, +description+, +params_schema+, and +call(args)+ and
      # exposes them over MCP.
      #
      # Tools can return:
      #   - An object responding to #ok?/#ok and #output/#error_message (Ask::Result style)
      #   - A plain String (treated as success)
      #   - Any other value (treated as success, .to_s is used for the response)
      class ToolServer
        attr_reader :tools

        def initialize(tools = [])
          @tools = tools
          @tool_map = tools.each_with_object({}) { |t, h| h[t.name] = t }
        end

        def definitions
          @tools.map do |tool|
            schema = tool.params_schema || { type: "object", properties: {}, required: [] }
            defn = {
              name: tool.name,
              description: tool.description || "",
              inputSchema: schema
            }
            # 2025-11-25: optional display metadata (SEP-973 icons, title).
            # Only included when the tool object provides them.
            defn[:title] = tool.title if tool.respond_to?(:title) && tool.title
            if tool.respond_to?(:icons) && tool.icons&.any?
              defn[:icons] = tool.icons
            end
            defn
          end
        end

        def call(name, arguments = {})
          tool = @tool_map[name]
          unless tool
            return error_result("Tool not found: #{name}")
          end

          normalized = deep_stringify_keys(arguments)
          result = tool.call(normalized)
          wrap_result(result)
        rescue StandardError => e
          if defined?(Ask::Tool::Halt) && e.is_a?(Ask::Tool::Halt)
            return { content: [{ type: "text", text: e.content.to_s }], isError: false }
          end
          error_result("#{e.class}: #{e.message}")
        end

        private

        def wrap_result(result)
          # Plain strings are always a success
          if result.is_a?(String)
            return text_result(result)
          end

          # Result-like objects (Ask::Result, OpenStruct, etc.)
          if result.respond_to?(:ok?) || result.respond_to?(:ok)
            ok = result.respond_to?(:ok?) ? result.ok? : result.ok
            return success_result(result, ok) if ok
            return error_result(result.respond_to?(:error_message) ? result.error_message : result.to_s)
          end

          # Everything else — treat as success. Hashes are JSON-serialized so
          # the content text is always a String (MCP content items require
          # string `text`). A String `:summary` is honored as a shorthand.
          text = if result.is_a?(Hash)
                   result[:summary].is_a?(String) ? result[:summary] : JSON.generate(result)
                 else
                   result.to_s
                 end
          text_result(text)
        end

        def success_result(result, _ok)
          output = result.respond_to?(:output) ? result.output : result.to_s
          text = if output.is_a?(Hash)
                   output[:summary].is_a?(String) ? output[:summary] : JSON.generate(output)
                 else
                   output.to_s
                 end
          text_result(text)
        end

        def error_result(message)
          { content: [{ type: "text", text: "Error: #{message}" }], isError: true }
        end

        # Builds a success result. Mirrors JSON text into `structuredContent`
        # (MCP 2025-06-18) when it parses, so clients can render a structured
        # view instead of an empty section.
        def text_result(text)
          { content: [{ type: "text", text: text }], isError: false }.merge(structured_content_for(text))
        end

        def structured_content_for(text)
          parsed = JSON.parse(text)
          return {} unless parsed.is_a?(Hash) || parsed.is_a?(Array)

          { structuredContent: parsed }
        rescue JSON::ParserError
          {}
        end

        def deep_stringify_keys(obj)
          case obj
          when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify_keys(v) }
          when Array then obj.map { |v| deep_stringify_keys(v) }
          else obj
          end
        end
      end
    end
  end
end
