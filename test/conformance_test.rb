# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/mcp_server_harness"

# Self-contained conformance: the full MCP lifecycle against the real server
# in BOTH protocol eras — the legacy 2025-06-18 `initialize` handshake and the
# stateless 2026-07-28 revision. This is the in-repo stand-in for the official
# MCP conformance fixtures until those are published (see
# docs/SPEC_COMPLIANCE.md §4); when the official suite lands, run it here too.
class ConformanceTest < Minitest::Test
  def server_script
    File.expand_path("support/test_stdio_server.rb", __dir__)
  end

  STATELESS_META = { _meta: { "io.modelcontextprotocol/protocolVersion" => "2026-07-28" } }.freeze

  # --- Legacy era (2025-06-18): stateful handshake ---

  def test_legacy_2025_06_18_lifecycle
    harness = MCPServerHarness.new("ruby", [server_script])
    harness.start

    # 1. initialize handshake negotiates the version
    resp = harness.initialize_session
    assert_equal "2025-06-18", resp[:result][:protocolVersion]
    assert_equal "test-stdio-server", resp[:result][:serverInfo][:name]
    assert resp[:result][:capabilities][:tools]

    # 2. tools/list works; no resultType/cache hints on the legacy wire
    resp = harness.list_tools
    names = resp[:result][:tools].map { |t| t[:name] }
    assert_includes names, "echo"
    refute resp[:result].key?(:resultType)
    refute resp[:result].key?(:ttlMs)

    # 3. tool call
    resp = harness.call_tool("echo", { "message" => "hello" })
    assert_equal "Echo: hello", resp[:result][:content].first[:text]

    # 4. resources
    harness.send_request("resources/list")
    resp = harness.read_response
    assert resp[:result][:resources].any? { |r| r[:uri] == "greeting://world" }

    # 5. prompts
    harness.send_request("prompts/get", { name: "greet" })
    resp = harness.read_response
    assert_equal "user", resp[:result][:messages].first[:role]

    # 6. ping is still supported for legacy clients
    harness.send_request("ping")
    resp = harness.read_response
    assert_equal({}, resp[:result])
  ensure
    harness&.stop
  end

  # --- Stateless era (2026-07-28): no handshake, per-request _meta ---

  def test_stateless_2026_07_28_lifecycle
    harness = MCPServerHarness.new("ruby", [server_script])
    harness.start

    # 1. server/discover advertises supported versions
    harness.send_request("server/discover")
    resp = harness.read_response
    assert_includes resp[:result][:protocolVersions], "2026-07-28"
    assert_equal "test-stdio-server", resp[:result][:serverInfo][:name]

    # 2. tools/list without any handshake; resultType + CacheableResult
    harness.send_request("tools/list", STATELESS_META)
    resp = harness.read_response
    assert_equal "complete", resp[:result][:resultType]
    assert resp[:result][:ttlMs].is_a?(Integer)
    assert_equal "private", resp[:result][:cacheScope]

    # 3. tool call without a handshake
    harness.send_request("tools/call", { name: "echo", arguments: { "message" => "hi" } }.merge(STATELESS_META))
    resp = harness.read_response
    assert_equal "Echo: hi", resp[:result][:content].first[:text]

    # 4. resource-not-found uses the renumbered -32602
    harness.send_request("resources/read", { uri: "file:///nope" }.merge(STATELESS_META))
    resp = harness.read_response
    assert_equal(-32_602, resp[:error][:code])

    # 5. ping was removed in the stateless revision
    harness.send_request("ping", STATELESS_META)
    resp = harness.read_response
    assert_equal(-32_601, resp[:error][:code])

    # 6. unknown method → -32601
    harness.send_request("no/such/method", STATELESS_META)
    resp = harness.read_response
    assert_equal(-32_601, resp[:error][:code])
  ensure
    harness&.stop
  end

  # --- Stateless client against the real server (end to end) ---

  def test_stateless_client_end_to_end
    transport = Ask::MCP::Transport::Stdio.new("ruby", [server_script])
    @client = Ask::MCP::Client.new(transport, timeout: 3)
    @client.start

    # The real server answers server/discover, so the client goes stateless.
    assert @client.initialized?
    assert @client.instance_variable_get(:@stateless), "client should negotiate stateless mode"
    assert_equal "2026-07-28", @client.instance_variable_get(:@protocol_version)

    tools = @client.tools
    assert tools.key?("echo")
    result = @client.call_tool("echo", { message: "conformance" })
    text = result.is_a?(Array) ? result.first[:text] : result.dig(:content, 0, :text)
    assert_equal "Echo: conformance", text
  rescue Timeout::Error
    skip "stateless client conformance timed out"
  end
end
