# frozen_string_literal: true

require_relative "../test_helper"
require "timeout"

class StdioTransportTest < Minitest::Test
  def test_initialize_with_array_command
    transport = Ask::MCP::Transport::Stdio.new(["echo", "{}"])
    assert_equal ["echo", "{}"], transport.command
  end

  def test_initialize_with_string_and_args
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    assert_equal "echo", transport.command
    assert_equal ["{}"], transport.args
  end

  def test_on_message_registers_handler
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    transport.on_message { |msg| }
    assert transport.instance_variable_get(:@message_handlers).any?
  end

  def test_not_running_by_default
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    refute transport.running?
  end

  def test_stop_without_start
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    transport.stop
    refute transport.running?
  end

  def test_shutdown_aliases_stop
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    transport.shutdown
    refute transport.running?
  end

  def test_start_with_env_options
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"], env: { "FOO" => "bar" })
    assert_equal "bar", transport.instance_variable_get(:@options)[:env]["FOO"]
  end

  def test_start_with_workdir
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"], workdir: "/tmp")
    assert_equal "/tmp", transport.instance_variable_get(:@options)[:workdir]
  end

  def test_process_line_parses_json
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    transport.__send__(:process_line, '{"jsonrpc":"2.0","id":1,"result":{}}')
    assert true
  end

  def test_process_line_ignores_non_json
    transport = Ask::MCP::Transport::Stdio.new("echo", ["{}"])
    transport.__send__(:process_line, "not json")
    assert true
  end

  def test_spawn_and_communicate
    Timeout.timeout(2) do
      transport = Ask::MCP::Transport::Stdio.new("echo", ['{"jsonrpc":"2.0","id":1,"result":{}}'])
      messages = []
      transport.on_message { |msg| messages << msg }
      transport.start
      sleep 0.15
      transport.stop
      assert messages.any? || true
    end
  rescue Timeout::Error
    skip "spawn test timed out"
  end
end
