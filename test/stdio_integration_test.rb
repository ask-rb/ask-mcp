# frozen_string_literal: true

require_relative "test_helper"

class StdioIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path("support/mock_mcp_server.rb", __dir__)
  end

  def teardown
    @server&.stop rescue nil
    @client&.stop rescue nil
  end

  def test_transport_start_and_stop
    transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
    transport.start
    assert transport.running?
    transport.stop
    refute transport.running?
  end

  def test_transport_send_and_receive
    received = []
    transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
    transport.on_message { |msg| received << msg }
    transport.start

    req = Ask::MCP::Native::Messages::Request.new(method: "initialize", id: 1)
    transport.send(req)

    # Wait for response — poll instead of fixed sleep
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    while received.empty? && (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) < 3
      sleep 0.05
    end

    assert_equal 1, received.size
    response = received.first
    assert_instance_of Ask::MCP::Native::Messages::Response, response
    assert response.success?
    refute_nil response.result[:serverInfo]
    transport.stop
  end

  def test_tool_discovery
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    tools = @client.tools
    assert_instance_of Hash, tools
    assert tools.key?("echo")
    assert tools.key?("add")
  end

  def test_call_tool
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    result = @client.call_tool("echo", message: "hello world")
    assert result.is_a?(Array)
    assert result.any? { |c| c[:text]&.include?("hello world") }
  end

  def test_call_tool_with_args
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    result = @client.call_tool("add", a: 2, b: 3)
    assert result.is_a?(Array)
    assert result.any? { |c| c[:text]&.include?("5") }
  end

  def test_resource_discovery
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    resources = @client.resources
    assert_instance_of Hash, resources
    assert resources.key?("greeting://world")
  end

  def test_read_resource
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    content = @client.read_resource("greeting://world")
    assert content.is_a?(Array)
  end

  def test_prompt_discovery
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    prompts = @client.prompts
    assert_instance_of Hash, prompts
    assert prompts.key?("greet")
  end

  def test_get_prompt
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    messages = @client.get_prompt("greet", name: "World")
    assert messages.is_a?(Array)
  end

  def test_client_lifecycle
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start
    assert @client.initialized?
    @client.stop
    refute @client.initialized?
  end

  def test_caches_tools
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    tools1 = @client.tools
    tools2 = @client.tools
    assert_same tools1, tools2
  end

  def test_uncached_tools
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    tools = @client.tools
    assert tools.key?("echo")
  end

  def test_error_handling
    @client = Ask::MCP::Client.new(
      Ask::MCP::Transport::Stdio.new("ruby", [@script_path]),
      timeout: 5
    )
    @client.start

    assert_raises(Ask::MCP::ProtocolError) { @client.call_tool("nonexistent", {}) }
  end
end
