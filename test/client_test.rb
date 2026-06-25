# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  def setup
    @transport = build_transport
    @client = Ask::MCP::Client.new(@transport, timeout: 1)
  end

  def test_initialize
    refute @client.initialized?
    assert_equal({}, @client.capabilities)
  end

  def test_protocol_version_defined
    assert_equal "0.1.0", Ask::MCP::Client::PROTOCOL_VERSION
  end

  def test_connect_method
    client = Ask::MCP.connect(@transport)
    assert_instance_of Ask::MCP::Client, client
  end

  def test_factory_methods_return_client_instances
    assert_instance_of Ask::MCP::Client, Ask::MCP.from_stdio("echo", ["hello"])
    assert_instance_of Ask::MCP::Client, Ask::MCP.from_sse("http://localhost:8080/sse")
    assert_instance_of Ask::MCP::Client, Ask::MCP.from_http("http://localhost:8080/mcp")
  end

  def test_tools_raises_without_start
    assert_raises(Ask::MCP::ConnectionError) { @client.tools }
  end

  def test_resources_raises_without_start
    assert_raises(Ask::MCP::ConnectionError) { @client.resources }
  end

  def test_prompts_raises_without_start
    assert_raises(Ask::MCP::ConnectionError) { @client.prompts }
  end

  def test_read_resource_raises_without_start
    assert_raises(Ask::MCP::ConnectionError) { @client.read_resource("file:///tmp/test") }
  end

  def test_get_prompt_raises_without_start
    assert_raises(Ask::MCP::ConnectionError) { @client.get_prompt("test_prompt") }
  end

  def test_stop_before_start
    @client.stop
    refute @client.initialized?
  end

  def test_server_info_defaults_to_empty
    assert_equal({}, @client.server_info)
  end

  def test_options_passthrough
    client = Ask::MCP::Client.new(@transport, timeout: 30, validate: true, no_cache: true)
    opts = client.instance_variable_get(:@options)
    assert_equal 30, opts[:timeout]
    assert opts[:validate]
    assert opts[:no_cache]
  end

  def test_handle_notification_resets_tools_cache
    @client.instance_variable_set(:@tools_cache, { cached: true })
    notification = Ask::MCP::Native::Messages::Notification.new(method: "notifications/tools/list_changed")
    @client.__send__(:handle_notification, notification)
    assert_nil @client.instance_variable_get(:@tools_cache)
  end

  def test_handle_notification_resets_resources_cache
    @client.instance_variable_set(:@resources_cache, { cached: true })
    notification = Ask::MCP::Native::Messages::Notification.new(method: "notifications/resources/list_changed")
    @client.__send__(:handle_notification, notification)
    assert_nil @client.instance_variable_get(:@resources_cache)
  end

  def test_handle_notification_resets_prompts_cache
    @client.instance_variable_set(:@prompts_cache, { cached: true })
    notification = Ask::MCP::Native::Messages::Notification.new(method: "notifications/prompts/list_changed")
    @client.__send__(:handle_notification, notification)
    assert_nil @client.instance_variable_get(:@prompts_cache)
  end

  def test_handle_notification_ignores_unknown
    @client.instance_variable_set(:@tools_cache, { cached: true })
    notification = Ask::MCP::Native::Messages::Notification.new(method: "unknown/event")
    @client.__send__(:handle_notification, notification)
    assert @client.instance_variable_get(:@tools_cache)
  end

  private

  def build_transport
    transport = Object.new
    transport.define_singleton_method(:on_message) { |&block| }
    transport.define_singleton_method(:start) { }
    transport.define_singleton_method(:stop) { }
    transport.define_singleton_method(:send) { |msg| }
    transport
  end
end
