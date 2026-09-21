# frozen_string_literal: true

require "ask/runtime"

module Ask
  module MCP
    # Bridges an MCP Client into the Ask::Runtime::ToolExecutor interface.
    #
    # Wraps an Ask::MCP::Client and implements the execute() contract so that
    # MCP tools can participate in Ask::Runtime tool-call pipelines.
    #
    #   executor = Ask::MCP::RuntimeExecutor.new(client)
    #   result = executor.execute(tool_call, context: ctx)
    #
    # Responsibilities:
    # - Delegates to client.call_tool(tool_call.tool_name, tool_call.input)
    # - Normalizes MCP content/result shapes into ToolResult.success or failure
    # - Honors context cancellation before calling the client
    # - Emits ToolStarted / ToolCompleted / ToolFailed / ToolCancelled events
    #   via context.event_sink with terminal snapshots
    #
    # Error handling:
    # - MCP isError responses → ToolResult.failure
    # - Client exceptions (ProtocolError, ConnectionError) → ToolResult.failure
    # - Malformed/empty results → ToolResult.success with nil output
    #
    class RuntimeExecutor
      include Ask::Runtime::ToolExecutor

      # @param client [Ask::MCP::Client] an initialized MCP client
      def initialize(client)
        @client = client
      end

      # @return [Ask::MCP::Client] the underlying MCP client
      attr_reader :client

      # Create a RuntimeExecutor from a client.
      #
      # @param client [Ask::MCP::Client] an initialized MCP client
      # @return [RuntimeExecutor]
      def self.from_client(client)
        new(client)
      end

      # Execute a tool call via the MCP client.
      #
      # @param tool_call [Ask::Runtime::ToolCall] the tool-call request
      # @param context [Ask::Runtime::ExecutionContext, nil] execution context
      # @return [Ask::Runtime::ToolResult] normalized result
      def execute(tool_call, context: nil)
        context ||= Ask::Runtime::ExecutionContext.new

        started_call = transition(tool_call, :running, started_at: Time.now)
        emit_event(Ask::Runtime::Events::ToolStarted,
                    tool_call: started_call, execution_context: context)

        return cancel(tool_call, context, "Cancelled before execution") if context.cancelled?

        result = call_tool(tool_call)
        return cancel(tool_call, context, "Cancelled during execution") if context.cancelled?

        finished_at = Time.now
        duration = finished_at - started_call.started_at

        terminal_call = started_call.with(
          state: result.success? ? :completed : :failed,
          tool_result: result,
          finished_at: finished_at
        )

        event_class = result.success? ? Ask::Runtime::Events::ToolCompleted : Ask::Runtime::Events::ToolFailed
        emit_event(event_class,
                    tool_call: terminal_call, tool_result: result,
                    execution_context: context, duration: duration)

        result_with_duration(result, duration)
      end

      private

      def call_tool(tool_call)
        response = @client.call_tool(tool_call.tool_name, tool_call.input)
        normalize_result(response)
      rescue Ask::MCP::Error, Ask::MCP::ConnectionError => e
        Ask::Runtime::ToolResult.failure(e.message)
      rescue => e
        Ask::Runtime::ToolResult.failure("#{e.class}: #{e.message}")
      end

      # Normalize MCP tools/call response shapes into a ToolResult.
      #
      # MCP responses are one of:
      #   Array  — [{ type: "text", text: "..." }, ...]
      #   Hash   — { content: [...], isError: bool, ... }
      #   String — plain text (some servers)
      #   nil    — empty response
      def normalize_result(response)
        error = error?(response)
        output = extract_output(response)

        if error
          msg = extract_error_message(response) ||
                (output.is_a?(String) ? output : nil) ||
                "MCP tool error"
          Ask::Runtime::ToolResult.failure(msg)
        else
          Ask::Runtime::ToolResult.success(data: output)
        end
      end

      def extract_output(response)
        case response
        when Array
          extract_from_content_array(response)
        when Hash
          if response[:content] || response["content"]
            extract_from_content_array(response[:content] || response["content"])
          else
            response
          end
        when String
          response
        when nil
          nil
        else
          response.to_s
        end
      end

      def extract_from_content_array(array)
        return nil if array.nil? || array.empty?

        if array.length == 1
          item = array.first
          if item.is_a?(Hash) && (item[:text] || item["text"])
            return item[:text] || item["text"]
          end
          return array
        end

        texts = array.filter_map do |item|
          item.is_a?(Hash) ? (item[:text] || item["text"]) : item&.to_s
        end
        texts.length == array.length ? texts.join("\n") : array
      end

      def error?(response)
        return false unless response.is_a?(Hash)

        response[:isError] || response["isError"]
      end

      def extract_error_message(response)
        return unless response.is_a?(Hash)

        content = response[:content] || response["content"]
        return unless content.is_a?(Array) && content.any?

        first = content.first
        first[:text] || first["text"] if first.is_a?(Hash)
      end

      def cancel(tool_call, context, reason)
        result = Ask::Runtime::ToolResult.cancelled(reason)
        terminal_call = tool_call.with(
          state: :cancelled,
          tool_result: result,
          finished_at: Time.now
        )
        duration = terminal_call.finished_at - terminal_call.created_at

        emit_event(Ask::Runtime::Events::ToolCancelled,
                    tool_call: terminal_call, tool_result: result,
                    execution_context: context, duration: duration)

        result
      end

      def transition(tool_call, state, **attrs)
        tool_call.with(state: state, **attrs)
      end

      def result_with_duration(result, duration)
        return result if result.duration == duration

        Ask::Runtime::ToolResult.new(
          result: result.result,
          outcome: result.outcome,
          duration: duration
        )
      end

      def emit_event(event_class, **args)
        timestamp = Time.now
        event = event_class.new(**args, timestamp: timestamp)
        sink = args[:execution_context].event_sink
        event_type = event_class.name.split("::").last
                     .gsub(/([a-z])([A-Z])/, '\1_\2')
                     .downcase
                     .to_sym
        sink.emit(event_type, event: event)
      rescue => e
        warn "[ask-mcp][runtime_executor] event emission failed: #{e.message}"
      end
    end
  end
end
