# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/mcp_server_harness"

class ServerStdioTest < Minitest::Test
  def server_script
    File.expand_path("../support/test_stdio_server.rb", __dir__)
  end

  def timeout_server_script
    File.expand_path("../support/test_timeout_server.rb", __dir__)
  end

  def setup
    @harness = MCPServerHarness.new("ruby", [server_script])
    @harness.start
  end

  def teardown
    @harness.stop
  rescue
  end

  # --- Protocol lifecycle ---

  def test_initialize_handshake
    resp = @harness.initialize_session
    assert resp[:result], "Expected initialize result, got: #{resp[:error]}"
    assert_equal "test-stdio-server", resp[:result][:serverInfo][:name]
    assert resp[:result][:capabilities][:tools], "Expected tools capability"
  end

  def test_notifications_initialized_produces_no_response
    @harness.send_request("initialize", {
      protocolVersion: "0.1.0",
      capabilities: {},
      clientInfo: { name: "test", version: "1.0" }
    })
    resp = @harness.read_response
    assert resp[:result], "initialize should succeed"

    @harness.send_notification("notifications/initialized")
    @harness.buffer = +""
    result = read_with_timeout(@harness, 0.3)
    assert_nil result, "Notification should not produce a response"
  end

  def test_tools_list_before_initialize_returns_error
    @harness.send_request("tools/list")
    resp = @harness.read_response
    assert resp[:error], "Expected error before initialize"
  end

  def test_tools_list_after_initialize
    @harness.initialize_session
    resp = @harness.list_tools
    assert resp[:result], "Expected tools list, got: #{resp[:error]}"
    tools = resp[:result][:tools]
    assert_kind_of Array, tools
    names = tools.map { |t| t[:name] }
    assert_includes names, "echo"
    assert_includes names, "reverse"
    assert_includes names, "slow"
    assert_includes names, "multiline"
  end

  def test_tools_list_definitions_have_schema
    @harness.initialize_session
    resp = @harness.list_tools
    echo_def = resp[:result][:tools].find { |t| t[:name] == "echo" }
    assert echo_def[:inputSchema], "echo should have inputSchema"
    props = echo_def[:inputSchema][:properties]
    assert props.key?("message") || props.key?(:message),
           "echo should have message param"
  end

  # --- Tool calling ---

  def test_tool_call_success
    @harness.initialize_session
    resp = @harness.call_tool("echo", { "message" => "hello" })
    assert resp[:result], "Expected success, got: #{resp[:error]}"
    assert_equal false, resp.dig(:result, :isError)
    text = resp[:result][:content].first[:text]
    assert_equal "Echo: hello", text
  end

  def test_tool_call_unknown_tool
    @harness.initialize_session
    resp = @harness.call_tool("nonexistent", {})
    assert resp[:result], "Expected result, got: #{resp[:error]}"
    assert resp.dig(:result, :isError), "Expected error for unknown tool"
    assert_match(/Tool not found/, resp[:result][:content].first[:text])
  end

  def test_tool_call_with_empty_args
    @harness.initialize_session
    resp = @harness.call_tool("noop", {})
    assert resp[:result], "Expected success, got: #{resp[:error]}"
    assert_equal false, resp.dig(:result, :isError)
  end

  def test_tool_call_error_result
    @harness.initialize_session
    resp = @harness.call_tool("fail", {})
    assert resp[:result], "Expected result, got: #{resp[:error]}"
    assert resp.dig(:result, :isError), "Expected error for failing tool"
    assert_match(/FAIL/, resp[:result][:content].first[:text])
  end

  def test_tool_call_numeric_result
    @harness.initialize_session
    resp = @harness.call_tool("add", { "a" => 2, "b" => 3 })
    assert resp[:result], "Expected success, got: #{resp[:error]}"
    assert_equal "5", resp[:result][:content].first[:text]
  end

  # --- Request ID deduplication ---

  def test_retry_same_id_returns_cached_result
    @harness.initialize_session

    msg = '{"jsonrpc":"2.0","id":42,"method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":7}}}'
    @harness.stdin.puts(msg)
    @harness.stdin.flush
    resp1 = @harness.read_response
    assert_equal "12", resp1[:result][:content].first[:text]

    @harness.buffer = +""
    @harness.stdin.puts(msg)
    @harness.stdin.flush
    resp2 = @harness.read_response
    assert_equal "12", resp2[:result][:content].first[:text],
                 "Retry with same ID should return cached result"
  end

  def test_different_ids_dont_cache_miss
    @harness.initialize_session

    @harness.send_request("tools/call", { name: "add", arguments: { a: 1, b: 2 } }, id: 100)
    resp1 = @harness.read_response
    assert_equal "3", resp1[:result][:content].first[:text]

    @harness.send_request("tools/call", { name: "add", arguments: { a: 3, b: 4 } }, id: 101)
    resp2 = @harness.read_response
    assert_equal "7", resp2[:result][:content].first[:text],
                 "Different IDs with different args should recompute"
  end

  def test_cache_eviction_doesnt_break
    @harness.initialize_session

    # Send just enough to trigger one eviction (MAX_RESULT_CACHE = 100)
    60.times do |i|
      @harness.send_request("tools/call", { name: "noop", arguments: {} }, id: i + 1)
      @harness.read_response
    end

    # After many requests, a new one should still work
    @harness.send_request("tools/call", { name: "add", arguments: { a: 10, b: 20 } }, id: 99)
    resp = @harness.read_response
    assert_equal "30", resp[:result][:content].first[:text],
                 "Should still work after many cached entries"
  end

  # --- Tool timeout ---

  def test_tool_timeout_returns_error
    script = timeout_server_script
    harness = MCPServerHarness.new("ruby", [script])
    harness.start
    harness.initialize_session

    harness.send_request("tools/call", { name: "slow", arguments: { seconds: 3 } }, id: 10)
    resp = harness.read_response(timeout: 4)
    assert resp[:result], "Expected result, got: #{resp[:error]}"
    assert resp.dig(:result, :isError), "Expected error for timed-out tool"
    assert_match(/timed out/i, resp[:result][:content].first[:text])
  ensure
    harness.stop
  end

  def test_tool_timeout_leaves_server_alive
    script = timeout_server_script
    harness = MCPServerHarness.new("ruby", [script])
    harness.start
    harness.initialize_session

    harness.send_request("tools/call", { name: "slow", arguments: { seconds: 3 } }, id: 11)
    harness.read_response(timeout: 4)

    harness.send_request("tools/call", { name: "slow", arguments: { seconds: 0.1 } }, id: 12)
    resp = harness.read_response
    assert resp[:result], "Expected success after timeout"
    assert_equal false, resp.dig(:result, :isError),
                 "Subsequent fast call should succeed after timeout"
  ensure
    harness.stop
  end

  # --- SIGTERM graceful shutdown ---

  def test_sigterm_triggers_shutdown
    @harness.initialize_session
    pid = @harness.pid
    assert pid > 0, "Server should have a PID"

    Process.kill("TERM", pid)

    begin
      Timeout.timeout(3) do
        @harness.wait_thr.value
      end
    rescue Timeout::Error
      Process.kill("KILL", pid) rescue nil
      flunk "Server did not exit within 3s of SIGTERM"
    end

    refute @harness.wait_thr.alive?, "Server should have exited after SIGTERM"
  end

  # --- Multiline JSON safety ---

  def test_multiline_output_preserved
    @harness.initialize_session
    resp = @harness.call_tool("multiline", {})
    assert resp[:result], "Expected success, got: #{resp[:error]}"
    text = resp[:result][:content].first[:text]
    assert_includes text, "line one"
    assert_includes text, "line two"
    assert_includes text, "line three"
  end

  def test_multiline_output_is_valid_json_roundtrip
    @harness.initialize_session
    resp = @harness.call_tool("multiline", {})
    json = JSON.generate(resp)
    parsed = JSON.parse(json, symbolize_names: true)
    text = parsed.dig(:result, :content, 0, :text)
    assert_includes text, "line one"
    assert_includes text, "line two"
  end

  def test_multiline_unicode_preserved
    @harness.initialize_session
    resp = @harness.call_tool("multiline", {})
    text = resp[:result][:content].first[:text]
    assert_includes text, "\u2603", "Should preserve snowman"
    assert_includes text, "\u2728", "Should preserve sparkles"
  end

  # --- Unknown method ---

  def test_unknown_method_returns_error
    @harness.initialize_session
    @harness.send_request("bogus/method")
    resp = @harness.read_response
    assert resp[:error], "Expected error for unknown method"
    assert_equal(-32601, resp[:error][:code])
  end

  # --- Ping ---

  def test_ping_returns_empty_result
    @harness.initialize_session
    @harness.send_request("ping")
    resp = @harness.read_response
    assert resp[:result], "Expected result for ping, got: #{resp[:error]}"
    assert_equal({}, resp[:result])
  end

  # --- Edge cases ---

  def test_graceful_shutdown_on_stdin_close
    @harness.initialize_session
    @harness.stdin.close
    exit_status = @harness.wait_thr.value
    assert exit_status.success?,
           "Expected clean exit, got: #{exit_status.inspect}"
  end

  def test_malformed_json_returns_parse_error
    @harness.stdin.puts("not valid json\n")
    @harness.stdin.flush
    resp = @harness.read_response
    assert resp[:error], "Expected parse error"
    assert_equal(-32700, resp[:error][:code])
  end

  def test_stray_newlines_ignored
    @harness.initialize_session
    @harness.stdin.puts("\n\n  \n")
    @harness.stdin.flush
    sleep 0.1
    resp = @harness.call_tool("echo", { "message" => "still works" })
    assert resp[:result], "Expected success after stray newlines"
  end

  def test_sequential_tool_calls_with_unique_ids
    @harness.initialize_session
    [10, 20, 30].each_with_index do |id, i|
      @harness.send_request("tools/call",
        { name: "echo", arguments: { "message" => "call #{i}" } }, id: id)
      resp = @harness.read_response
      assert resp[:result], "Call #{i} failed: #{resp[:error]}"
      assert_equal "Echo: call #{i}", resp[:result][:content].first[:text]
    end
  end

  # --- Debug mode ---

  def test_debug_mode_emits_stderr_logs
    script = server_script
    harness = MCPServerHarness.new("ruby", [script], env: { "DEBUG" => "1" })
    harness.start
    stderr_output = harness.wait_for_stderr(/test-stdio-server/)
    assert_match(/Server starting/, stderr_output)
    assert_match(/Tools:/, stderr_output)
    harness.initialize_session
    harness.call_tool("echo", { "message" => "x" })
    call_log = harness.wait_for_stderr(/tools\/call/)
    assert_match(/echo/, call_log)
  ensure
    harness.stop
  end

  def test_no_debug_no_stderr
    @harness.initialize_session
    @harness.call_tool("echo", { "message" => "silent" })
    sleep 0.2
    stderr_output = @harness.stderr_output
    assert stderr_output.empty?,
           "Expected no stderr without DEBUG, got: #{stderr_output.inspect}"
  end

  private

  def read_with_timeout(harness, timeout_sec)
    Timeout.timeout(timeout_sec) do
      loop do
        char = harness.stdout.getc
        return nil if char.nil?
        harness.buffer << char
        if harness.buffer.end_with?("\n")
          line = harness.buffer.strip
          harness.buffer = +""
          next if line.empty?
          parsed = JSON.parse(line, symbolize_names: true)
          return parsed if parsed.key?(:id)
        end
      end
    end
  rescue Timeout::Error
    nil
  end
end
