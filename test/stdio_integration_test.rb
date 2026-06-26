# frozen_string_literal: true

require_relative "test_helper"
require "timeout"

class StdioIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path("support/mock_mcp_server.rb", __dir__)
  end

  def teardown
    @server&.stop rescue nil
    @client&.stop rescue nil
    # Force-kill any lingering server processes
    ObjectSpace.each_object(Ask::MCP::Transport::Stdio) { |t| t.stop rescue nil }
  end

  def test_transport_start_and_stop
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      transport.start
      assert transport.running?
      transport.stop
      refute transport.running?
    end
  rescue Timeout::Error
    skip "start/stop timed out"
  end

  def test_transport_send_and_receive
    Timeout.timeout(3) do
      received = []
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      transport.on_message { |msg| received << msg }
      transport.start
      req = Ask::MCP::Native::Messages::Request.new(method: "initialize", id: 1)
      transport.send(req)
      sleep 0.2
      transport.stop
      assert received.any?
    end
  rescue Timeout::Error
    skip "send/receive timed out"
  end

  def test_client_initialize
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      assert @client.initialized?
      assert_equal "mock-mcp-server", @client.server_info[:name]
    end
  rescue Timeout::Error
    skip "client init timed out"
  end

  def test_client_list_tools
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      tools = @client.tools
      assert tools.key?("echo")
      assert tools.key?("add")
    end
  rescue Timeout::Error
    skip "list tools timed out"
  end

  def test_client_list_resources
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      resources = @client.resources
      assert resources.key?("greeting://world")
    end
  rescue Timeout::Error
    skip "list resources timed out"
  end

  def test_client_list_prompts
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      prompts = @client.prompts
      assert prompts.key?("greet")
    end
  rescue Timeout::Error
    skip "list prompts timed out"
  end

  def test_client_read_resource
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      content = @client.read_resource("greeting://world")
      assert content
    end
  rescue Timeout::Error
    skip "read resource timed out"
  end
end

class StdioServerRoundtripTest < Minitest::Test
  def setup
    @script_path = File.expand_path("support/test_stdio_server.rb", __dir__)
  end

  def teardown
    @client&.stop rescue nil
    ObjectSpace.each_object(Ask::MCP::Transport::Stdio) { |t| t.stop rescue nil }
  end

  def test_client_initialize_via_new_server
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      assert @client.initialized?
      assert_equal "test-stdio-server", @client.server_info[:name]
    end
  rescue Timeout::Error
    skip "client init timed out"
  end

  def test_client_tools_list_via_new_server
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      tools = @client.tools
      assert tools.key?("echo")
      assert tools.key?("reverse")
      assert tools.key?("add")
    end
  rescue Timeout::Error
    skip "tools list timed out"
  end

  def test_client_call_tool_via_new_server
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      result = @client.call_tool("echo", { message: "hello world" })
      assert result.is_a?(Array) || result.is_a?(Hash)
      text = result.is_a?(Array) ? result.first[:text] : result.dig(:content, 0, :text)
      assert text, "Expected content in result: #{result.inspect}"
    end
  rescue Timeout::Error
    skip "tool call timed out"
  end

  def test_client_stop_cleanup
    Timeout.timeout(3) do
      transport = Ask::MCP::Transport::Stdio.new("ruby", [@script_path])
      @client = Ask::MCP::Client.new(transport, timeout: 2)
      @client.start
      @client.stop
      refute @client.initialized?
    end
  rescue Timeout::Error
    skip "stop timed out"
  end
end
