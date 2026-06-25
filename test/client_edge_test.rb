# frozen_string_literal: true

require_relative "test_helper"

class ClientEdgeTest < Minitest::Test
  def test_client_options_passthrough
    transport = stub_transport
    client = Ask::MCP::Client.new(transport, timeout: 30, validate: true, no_cache: true)
    assert_equal 30, client.instance_variable_get(:@options)[:timeout]
    assert client.instance_variable_get(:@options)[:validate]
    assert client.instance_variable_get(:@options)[:no_cache]
  end

  def test_client_stop_before_start
    transport = stub_transport
    client = Ask::MCP::Client.new(transport)
    client.stop
    refute client.initialized?
  end

  private

  def stub_transport
    transport = Object.new
    transport.define_singleton_method(:on_message) { |&block| }
    transport.define_singleton_method(:start) { }
    transport.define_singleton_method(:stop) { }
    transport.define_singleton_method(:send) { |msg| }
    transport
  end
end
