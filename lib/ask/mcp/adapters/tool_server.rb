# frozen_string_literal: true

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
            {
              name: tool.name,
              description: tool.description || "",
              inputSchema: schema
            }
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
            return { content: [{ type: "text", text: result }], isError: false }
          end

          # Result-like objects (Ask::Result, OpenStruct, etc.)
          if result.respond_to?(:ok?) || result.respond_to?(:ok)
            ok = result.respond_to?(:ok?) ? result.ok? : result.ok
            return success_result(result, ok) if ok
            return error_result(result.respond_to?(:error_message) ? result.error_message : result.to_s)
          end

          # Everything else — treat as success
          text = result.is_a?(Hash) ? (result[:summary] || result.to_s) : result.to_s
          { content: [{ type: "text", text: text }], isError: false }
        end

        def success_result(result, _ok)
          output = result.respond_to?(:output) ? result.output : result.to_s
          text = output.is_a?(Hash) ? (output[:summary] || output.to_s) : output.to_s
          { content: [{ type: "text", text: text }], isError: false }
        end

        def error_result(message)
          { content: [{ type: "text", text: "Error: #{message}" }], isError: true }
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
