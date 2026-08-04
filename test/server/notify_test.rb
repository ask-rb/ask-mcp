# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/mcp_server_harness"

# Server→client change notifications (2026-07-28: notifications/*/list_changed,
# consumed by clients on the shared stdio channel or a subscriptions/listen
# stream). Each notify_* tool writes its notification before the tool response
# on the same thread, so ordering is deterministic.
class ServerNotifyTest < Minitest::Test
  def setup
    script = File.expand_path("../support/test_notify_server.rb", __dir__)
    @harness = MCPServerHarness.new("ruby", [script])
    @harness.start
  end

  def teardown
    @harness.stop
  rescue
  end

  def test_notify_tools_list_changed
    @harness.initialize_session
    @harness.send_request("tools/call", { name: "notify_tools", arguments: {} }, id: 90)

    notif = @harness.read_message(timeout: 3)
    refute_nil notif, "expected a notification before the tool response"
    assert_equal "notifications/tools/list_changed", notif[:method]
    refute notif.key?(:id), "notifications must not carry a JSON-RPC id"

    resp = @harness.read_response
    assert resp[:result], "tool call should still complete"
  end

  def test_notify_resources_list_changed
    @harness.initialize_session
    @harness.send_request("tools/call", { name: "notify_resources", arguments: {} }, id: 91)
    notif = @harness.read_message(timeout: 3)
    assert_equal "notifications/resources/list_changed", notif[:method]
    @harness.read_response
  end

  def test_notify_prompts_list_changed
    @harness.initialize_session
    @harness.send_request("tools/call", { name: "notify_prompts", arguments: {} }, id: 92)
    notif = @harness.read_message(timeout: 3)
    assert_equal "notifications/prompts/list_changed", notif[:method]
    @harness.read_response
  end

  def test_client_cache_invalidation_on_list_changed
    # The Ask::MCP::Client resets its tools cache when it sees the
    # notification — verified end-to-end against the real server.
    script = File.expand_path("../support/test_notify_server.rb", __dir__)
    transport = Ask::MCP::Transport::Stdio.new("ruby", [script])
    @client = Ask::MCP::Client.new(transport, timeout: 3)
    @client.start

    assert @client.tools.key?("notify_tools")
    @client.call_tool("notify_tools", {})

    wait_until(timeout: 3) { @client.instance_variable_get(:@tools_cache).nil? }
    assert_nil @client.instance_variable_get(:@tools_cache),
               "tools/list_changed must invalidate the client's tools cache"
  end
end
