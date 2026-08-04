# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/recording_transport"

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
    # Canonical constant is the single source of truth...
    assert_equal "2025-06-18", Ask::MCP::PROTOCOL_VERSION
    # ...and the Client alias must never drift from it.
    assert_equal Ask::MCP::PROTOCOL_VERSION, Ask::MCP::Client::PROTOCOL_VERSION
  end

  def test_initialize_sends_canonical_protocol_version
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    assert client.initialized?

    init = transport.sent.find { |m| m.method == "initialize" }
    refute_nil init, "expected an initialize request on the wire"
    assert_equal "2025-06-18", init.params[:protocolVersion]
    assert_equal Ask::MCP::PROTOCOL_VERSION, init.params[:protocolVersion]
  end

  # --- 2025-11-25: title/icons display metadata survives list round-trips ---

  def test_tools_preserve_title_and_icons
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: { tools: {} } },
      "tools/list" => {
        tools: [{
          name: "weather",
          title: "Weather",
          description: "Weather lookup",
          inputSchema: { type: "object" },
          icons: [{ src: "https://example.com/icon.png", mimeType: "image/png", sizes: ["48x48"] }]
        }]
      }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    tool = client.tools["weather"]
    assert_equal "Weather", tool.title
    assert_equal "https://example.com/icon.png", tool.icons.first[:src]
    assert_equal ["48x48"], tool.icons.first[:sizes]
  end

  def test_resources_preserve_title_and_icons
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: { resources: {} } },
      "resources/list" => {
        resources: [{
          uri: "file:///README.md",
          name: "README.md",
          title: "Project Documentation",
          mimeType: "text/markdown",
          icons: [{ src: "https://example.com/icon.png" }]
        }]
      }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    resource = client.resources["file:///README.md"]
    assert_equal "Project Documentation", resource.title
    assert_equal "https://example.com/icon.png", resource.icons.first[:src]
  end

  def test_prompts_preserve_title_and_icons
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: { prompts: {} } },
      "prompts/list" => {
        prompts: [{
          name: "greet",
          title: "Greet",
          description: "Generate a greeting",
          icons: [{ src: "https://example.com/icon.png" }]
        }]
      }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    prompt = client.prompts["greet"]
    assert_equal "Greet", prompt.title
    assert_equal "https://example.com/icon.png", prompt.icons.first[:src]
  end

  # --- Server-initiated requests: on_request / on_elicitation / on_sampling ---

  def test_on_request_responds_with_handler_result
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    client.on_request("custom/do") { |params| { echoed: params[:value] } }

    transport.inject(Ask::MCP::Native::Messages::Request.new(method: "custom/do", params: { value: 7 }, id: 99))
    response = transport.sent.find { |m| m.is_a?(Ask::MCP::Native::Messages::Response) && m.id == 99 }
    refute_nil response, "expected a response to the server request"
    assert response.success?
    assert_equal 7, response.result[:echoed]
  end

  def test_on_elicitation_responds_with_user_message
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    client.on_elicitation { |_params| { message: "42" } }

    transport.inject(Ask::MCP::Native::Messages::Request.new(method: "elicitation/create", params: { description: "What is 6x7?" }, id: 5))
    response = transport.sent.find { |m| m.is_a?(Ask::MCP::Native::Messages::Response) && m.id == 5 }
    refute_nil response, "expected a response to elicitation/create"
    assert response.success?
    assert_equal "42", response.result[:message]
  end

  def test_on_sampling_receives_tools_and_tool_choice
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    received = nil
    client.on_sampling do |params|
      received = params
      { role: "assistant", content: { type: "text", text: "hello" } }
    end

    server_params = {
      messages: [{ role: "user", content: { type: "text", text: "hi" } }],
      tools: [{ name: "calc", inputSchema: { type: "object" } }],
      toolChoice: "auto",
      maxTokens: 100
    }
    transport.inject(Ask::MCP::Native::Messages::Request.new(method: "sampling/createMessage", params: server_params, id: 6))
    response = transport.sent.find { |m| m.is_a?(Ask::MCP::Native::Messages::Response) && m.id == 6 }
    refute_nil response, "expected a response to sampling/createMessage"
    assert response.success?
    assert_equal "hello", response.result[:content][:text]
    # The 2025-11-25 tools/toolChoice params must reach the handler untouched.
    assert_equal "calc", received[:tools].first[:name]
    assert_equal "auto", received[:toolChoice]
  end

  def test_unhandled_server_request_returns_method_not_found
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start

    transport.inject(Ask::MCP::Native::Messages::Request.new(method: "unknown/method", params: {}, id: 42))
    response = transport.sent.find { |m| m.is_a?(Ask::MCP::Native::Messages::Response) && m.id == 42 }
    refute_nil response, "expected an error response for an unhandled request"
    refute response.success?
    assert_equal(-32_601, response.error[:code])
  end

  # --- 2026-07-28 stateless negotiation ---

  def test_stateless_client_skips_initialize_and_sends_meta
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25", "2026-07-28"],
        capabilities: { tools: {} },
        serverInfo: { name: "stateless-server", version: "1.0" }
      },
      "tools/list" => { tools: [] }
    )
    client = Ask::MCP::Client.new(transport, client_capabilities: { tools: {} })
    client.start

    assert client.initialized?
    assert_equal "stateless-server", client.server_info[:name]
    refute transport.sent.any? { |m| m.method == "initialize" },
           "stateless client must not perform the initialize handshake"

    client.tools
    tools_req = transport.sent.find { |m| m.method == "tools/list" }
    refute_nil tools_req
    meta = tools_req.params[:_meta]
    refute_nil meta, "stateless requests must carry _meta"
    assert_equal "2026-07-28", meta["io.modelcontextprotocol/protocolVersion"]
    assert_equal({ tools: {} }, meta["io.modelcontextprotocol/clientCapabilities"])
    assert_equal "ask-mcp", meta["io.modelcontextprotocol/clientInfo"][:name]
  end

  def test_legacy_server_still_uses_initialize_handshake
    # RecordingTransport auto-errors on server/discover (a legacy server has
    # no such method), so the client falls back to the handshake.
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "legacy-server", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start

    assert client.initialized?
    assert transport.sent.any? { |m| m.method == "server/discover" }, "client probes discover first"
    assert transport.sent.any? { |m| m.method == "initialize" }, "legacy server needs the handshake"
  end

  def test_legacy_revision_server_negotiates_then_handshakes
    # Server supports only ≤ 2025-11-25: discover succeeds but the handshake
    # is still required, with the negotiated version advertised.
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25"],
        capabilities: { tools: {} },
        serverInfo: { name: "legacy-1125", version: "1.0" }
      },
      "initialize" => { serverInfo: { name: "legacy-1125", version: "1.0" }, capabilities: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start

    assert client.initialized?
    init = transport.sent.find { |m| m.method == "initialize" }
    refute_nil init, "legacy-revision server still needs the handshake"
    assert_equal "2025-11-25", init.params[:protocolVersion]
  end

  def test_stateless_requests_do_not_carry_meta_after_stop
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25", "2026-07-28"],
        capabilities: {},
        serverInfo: { name: "stateless-server", version: "1.0" }
      }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    client.stop
    refute client.initialized?
  end

  # --- 2026-07-28 Multi Round-Trip Requests (MRTR) ---

  def test_mrtr_resolves_elicitation_and_retries
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25", "2026-07-28"],
        capabilities: { tools: {} },
        serverInfo: { name: "mrtr-server", version: "1.0" }
      }
    ) do |msg|
      if msg.method == "tools/call"
        if msg.params.key?(:inputResponses)
          # The retry (which carries the resolved input) completes.
          { content: [{ type: "text", text: "hello" }], resultType: "complete" }
        else
          # The first attempt needs more input via elicitation.
          {
            resultType: "input_required",
            requestState: "opaque-123",
            inputRequests: {
              "name" => { method: "elicitation/create", params: { message: "Your name?" } }
            }
          }
        end
      end
    end

    client = Ask::MCP::Client.new(transport)
    client.on_elicitation { |_params| { message: "Ada" } }
    client.start

    result = client.call_tool("greet", {})
    text = result.is_a?(Array) ? result.first[:text] : result.dig(:content, 0, :text)
    assert_equal "hello", text

    calls = transport.sent.select { |m| m.method == "tools/call" }
    assert_equal 2, calls.size, "MRTR must retry the original request once"
    retry_call = calls.last
    assert_equal({ "name" => { message: "Ada" } }, retry_call.params[:inputResponses])
    assert_equal "opaque-123", retry_call.params[:requestState], "requestState must be echoed verbatim"
    refute_equal calls.first.id, retry_call.id, "retry must use a new JSON-RPC id"
  end

  def test_mrtr_without_handler_raises_protocol_error
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25", "2026-07-28"],
        capabilities: { tools: {} },
        serverInfo: { name: "mrtr-server", version: "1.0" }
      }
    ) do |msg|
      if msg.method == "tools/call"
        { resultType: "input_required", inputRequests: { "k" => { method: "elicitation/create", params: {} } } }
      end
    end

    client = Ask::MCP::Client.new(transport)
    client.start
    assert_raises(Ask::MCP::ProtocolError) { client.call_tool("greet", {}) }
  end

  def test_mrtr_round_trip_limit_raises
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25", "2026-07-28"],
        capabilities: { tools: {} },
        serverInfo: { name: "mrtr-server", version: "1.0" }
      }
    ) do |msg|
      # The server keeps asking for input forever.
      if msg.method == "tools/call"
        { resultType: "input_required", inputRequests: {} }
      end
    end

    client = Ask::MCP::Client.new(transport)
    client.on_elicitation { |_params| { message: "x" } }
    client.start
    err = assert_raises(Ask::MCP::ProtocolError) { client.call_tool("greet", {}) }
    assert_match(/MRTR exceeded/, err.message)
  end

  def test_legacy_server_ignores_input_required_results
    # A legacy (handshake) client must NOT apply MRTR — resultType is only
    # meaningful in the stateless protocol. Here the server (incorrectly for a
    # legacy peer) returns resultType input_required; the client treats it as
    # an ordinary result.
    transport = RecordingTransport.new(
      "initialize" => { serverInfo: { name: "legacy", version: "1.0" }, capabilities: {} },
      "tools/call" => { resultType: "input_required", inputRequests: {} }
    )
    client = Ask::MCP::Client.new(transport)
    client.start
    result = client.call_tool("greet", {})
    assert_equal "input_required", result[:resultType]
    calls = transport.sent.select { |m| m.method == "tools/call" }
    assert_equal 1, calls.size, "legacy client must not retry"
  end

  # --- 2026-07-28: x-mcp-header validation (SEP-2243) ---

  def test_http_client_rejects_invalid_x_mcp_header_tools
    valid = Ask::MCP::Tool.from_h(
      name: "good",
      inputSchema: { type: "object", properties: { a: { type: "string", :'x-mcp-header' => "A" } } }
    )
    invalid = Ask::MCP::Tool.from_h(
      name: "bad",
      inputSchema: { type: "object", properties: { a: { type: "number", :'x-mcp-header' => "A" } } }
    )
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    client = Ask::MCP::Client.new(transport)
    filtered = client.__send__(:reject_invalid_mcp_header_tools, [valid, invalid])
    assert_equal ["good"], filtered.map(&:name), "invalid tool must be excluded from tools/list"
  end

  def test_stdio_client_ignores_x_mcp_header_validation
    invalid = Ask::MCP::Tool.from_h(
      name: "bad",
      inputSchema: { type: "object", properties: { a: { type: "number", :'x-mcp-header' => "A" } } }
    )
    transport = RecordingTransport.new
    client = Ask::MCP::Client.new(transport)
    filtered = client.__send__(:reject_invalid_mcp_header_tools, [invalid])
    assert_equal ["bad"], filtered.map(&:name), "non-HTTP transports may ignore x-mcp-header"
  end

  # --- 2026-07-28: OTel trace context in _meta (SEP-414) ---

  def test_stateless_requests_carry_configured_meta_fields
    trace = { "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" }
    transport = RecordingTransport.new(
      "server/discover" => {
        protocolVersions: ["2025-06-18", "2025-11-25", "2026-07-28"],
        capabilities: { tools: {} },
        serverInfo: { name: "otel-server", version: "1.0" }
      },
      "tools/list" => { tools: [] }
    )
    client = Ask::MCP::Client.new(transport, meta: trace)
    client.start
    client.tools

    tools_req = transport.sent.find { |m| m.method == "tools/list" }
    meta = tools_req.params[:_meta]
    assert_equal trace["traceparent"], meta["traceparent"],
                 "configured _meta fields (e.g. traceparent) must propagate"
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
    transport.define_singleton_method(:send) { |msg, _headers = {}| }
    transport
  end
end
