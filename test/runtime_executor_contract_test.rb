# frozen_string_literal: true

require_relative "test_helper"

class McpRuntimeExecutorContractTest < Minitest::Test
  include Ask::Runtime::Testing::ExecutorContract

  class Client
    def call_tool(_name, arguments)
      if arguments[:outcome] == :failure
        { content: [{ type: "text", text: "failed" }], isError: true }
      else
        [{ type: "text", text: "ok" }]
      end
    end
  end

  def test_mcp_executor_conforms_to_runtime_contract
    context_factory = ->(event_sink:, canceller: nil) do
      Ask::Runtime::ExecutionContext.new(
        session_id: "s_mcp", turn: 1, event_sink: event_sink, canceller: canceller
      )
    end

    assert_conforms_to_runtime_contract(
      Ask::MCP::RuntimeExecutor.new(Client.new),
      success_call: build_call(:success),
      failure_call: build_call(:failure),
      cancelled_call: build_call(:cancelled),
      context_factory: context_factory
    )
  end

  private

  def build_call(outcome)
    Ask::Runtime::ToolCall.new(
      id: "tc_#{outcome}", tool_name: "contract", input: { outcome: outcome },
      session_id: "s_mcp", turn: 1
    )
  end
end
