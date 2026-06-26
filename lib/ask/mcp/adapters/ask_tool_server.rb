# frozen_string_literal: true

module Ask
  module MCP
    module Adapters
      # Converts Ask::Tool instances into MCP tool definitions and dispatches
      # calls. This is the server-direction adapter — it takes Ask::Tool objects
      # (from tool packs like ask-tools-shell) and makes them available over MCP.
      #
      # Usage:
      #   adapter = AskToolServer.new(Ask::Tools::Shell.all)
      #   adapter.definitions  # => [{ name: "bash", description: "...", inputSchema: {...} }]
      #   adapter.call("bash", { command: "echo hi" })  # => { content: [...], isError: ... }
      class AskToolServer
        attr_reader :tools

        # @param tools [Array<#call, #name, #description, #params_schema>] tool instances to expose.
        #   Each tool must respond to name, description, params_schema, and call(args).
        def initialize(tools = [])
          @tools = tools
          @tool_map = tools.each_with_object({}) { |t, h| h[t.name] = t }
        end

        # MCP tool definitions for tools/list
        # @return [Array<Hash>]
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

        # Call a tool and wrap the result in MCP format
        # @param name [String] tool name
        # @param arguments [Hash] arguments (may have symbol or string keys)
        # @return [Hash] { content: [...], isError: true/false }
        def call(name, arguments = {})
          tool = @tool_map[name]
          unless tool
            return error_result("Tool not found: #{name}")
          end

          # Stringify keys — Ask::Tool subclasses expect string keys
          normalized = deep_stringify_keys(arguments)
          result = tool.call(normalized)
          wrap_result(result)
        rescue StandardError => e
          # If the tool raised Ask::Tool::Halt, treat it as a success
          if defined?(Ask::Tool::Halt) && e.is_a?(Ask::Tool::Halt)
            return { content: [{ type: "text", text: e.content.to_s }], isError: false }
          end
          error_result("#{e.class}: #{e.message}")
        end

        private

        def wrap_result(result)
          if result.respond_to?(:ok?) ? result.ok? : result.ok
            output = result.respond_to?(:output) ? result.output : result.to_s
            text = output.is_a?(Hash) ? (output[:summary] || output.to_s) : output.to_s
            { content: [{ type: "text", text: text }], isError: false }
          else
            msg = result.respond_to?(:error_message) ? result.error_message : result.to_s
            { content: [{ type: "text", text: "Error: #{msg}" }], isError: true }
          end
        end

        def error_result(message)
          { content: [{ type: "text", text: message }], isError: true }
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
