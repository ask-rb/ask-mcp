# frozen_string_literal: true

require_relative "../test_helper"
require "httpx"
require "base64"

# In-memory stand-ins for HTTPX/HTTP responses so transport behavior is
# asserted without a network.
class FakeHTTPClient
  attr_reader :posts

  def initialize(&responder)
    @responder = responder
    @posts = []
  end

  def post(url, body: nil, headers: {})
    @posts << { url: url, body: body, headers: headers }
    @responder.call(body, headers)
  end

  def close; end
end

class FakeStreamableResponse
  attr_reader :status, :content_type, :chunks

  def initialize(status, content_type, chunks)
    @status = status
    @content_type = content_type
    @chunks = chunks
  end

  def headers
    { "content-type" => @content_type }
  end

  def body
    data = chunks
    Object.new.tap do |b|
      b.define_singleton_method(:to_s) { data.join }
      b.define_singleton_method(:each) { |&block| data.each { |c| block.call(c) } }
    end
  end
end

class StreamableHTTPTransportTest < Minitest::Test
  def test_initialize_with_url
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    assert_equal "http://localhost:8080/mcp", transport.url
    refute transport.running?
  end

  def test_initialize_with_options
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp",
      stream: true, timeout: 60, headers: { "X-Custom" => "value" })
    opts = transport.instance_variable_get(:@options)
    assert opts[:stream]
    assert_equal 60, opts[:timeout]
    assert_equal "value", opts[:headers]["X-Custom"]
  end

  def test_on_message_registers_handler
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    calls = []
    transport.on_message { |msg| calls << msg }
    assert transport.instance_variable_get(:@message_handlers).any?
  end

  def test_stop_without_start
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.stop
    refute transport.running?
  end

  def test_shutdown_aliases_stop
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.shutdown
    refute transport.running?
  end

  def test_start_sets_running
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.start
    assert transport.running?
    transport.stop
  end

  # --- 2026-07-28: request metadata headers + per-response content type ---

  def fake_transport(response)
    fake_client = FakeHTTPClient.new { |_body, _headers| response }
    HTTPX.stubs(:with).returns(fake_client)
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    transport.start
    transport
  end

  def json_response(body)
    FakeStreamableResponse.new(200, "application/json", [body])
  end

  def test_post_includes_request_metadata_headers
    transport = fake_transport(json_response('{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete"}}'))
    transport.protocol_version = "2026-07-28"

    messages = []
    transport.on_message { |m| messages << m }
    transport.send(Ask::MCP::Native::Messages::Request.new(
      method: "tools/call", params: { name: "get_weather", arguments: {} }, id: 1
    ))

    post = transport.instance_variable_get(:@http).posts.first
    assert_equal "tools/call", post[:headers]["Mcp-Method"]
    assert_equal "get_weather", post[:headers]["Mcp-Name"]
    assert_equal "2026-07-28", post[:headers]["MCP-Protocol-Version"]
    assert_includes post[:headers]["Accept"], "application/json"
    assert_includes post[:headers]["Accept"], "text/event-stream"
    assert messages.any?, "expected the JSON response to be delivered"
    assert_equal "complete", messages.first.result[:resultType]
  end

  def test_resources_read_sets_mcp_name_from_uri
    transport = fake_transport(json_response('{"jsonrpc":"2.0","id":1,"result":{}}'))
    transport.protocol_version = "2026-07-28"
    transport.start

    transport.send(Ask::MCP::Native::Messages::Request.new(
      method: "resources/read", params: { uri: "file:///project/config.json" }, id: 1
    ))
    post = transport.instance_variable_get(:@http).posts.first
    assert_equal "resources/read", post[:headers]["Mcp-Method"]
    assert_equal "file:///project/config.json", post[:headers]["Mcp-Name"]
  end

  def test_sse_response_stream_delivers_notifications_then_response
    chunks = [
      "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progress\":0.5}}\n\n",
      "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"complete\"}}\n\n"
    ]
    transport = fake_transport(FakeStreamableResponse.new(200, "text/event-stream", chunks))
    messages = []
    transport.on_message { |m| messages << m }
    transport.start

    transport.send(Ask::MCP::Native::Messages::Request.new(method: "tools/call", params: { name: "x" }, id: 1))

    assert_equal 2, messages.size
    assert_equal "notifications/progress", messages.first.method
    assert_equal "complete", messages.last.result[:resultType]
  end

  def test_sse_comment_lines_ignored
    chunks = [
      ":\n\n",
      "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n"
    ]
    transport = fake_transport(FakeStreamableResponse.new(200, "text/event-stream", chunks))
    messages = []
    transport.on_message { |m| messages << m }
    transport.start

    transport.send(Ask::MCP::Native::Messages::Request.new(method: "tools/call", params: { name: "x" }, id: 1))

    assert_equal 1, messages.size, "SSE keep-alive comments must be ignored"
  end

  def test_non_200_raises_connection_error
    transport = fake_transport(FakeStreamableResponse.new(500, "text/plain", ["boom"]))
    transport.start
    assert_raises(Ask::MCP::ConnectionError) do
      transport.send(Ask::MCP::Native::Messages::Request.new(method: "tools/call", params: { name: "x" }, id: 1))
    end
  end

  # --- Value encoding (Mcp-Name / Mcp-Param-*) ---

  def test_encode_header_value
    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    assert_equal "us-west1", transport.encode_header_value("us-west1")
    assert_equal "42", transport.encode_header_value(42)
    assert_equal "true", transport.encode_header_value(true)
    assert_equal "=?base64?#{Base64.strict_encode64('Hello, 世界')}?=", transport.encode_header_value("Hello, 世界")
    assert transport.encode_header_value(" padded ").start_with?("=?base64?"), "leading/trailing whitespace must be encoded"
    assert transport.encode_header_value("line1\nline2").start_with?("=?base64?"), "control characters must be encoded"
    assert transport.encode_header_value("=?base64?literal?=").start_with?("=?base64?"), "sentinel-like values must be encoded"
  end

  def test_mcp_name_uses_encoded_value_for_non_ascii
    transport = fake_transport(json_response('{"jsonrpc":"2.0","id":1,"result":{}}'))
    transport.protocol_version = "2026-07-28"
    transport.start

    transport.send(Ask::MCP::Native::Messages::Request.new(
      method: "prompts/get", params: { name: "héllo" }, id: 1
    ))
    post = transport.instance_variable_get(:@http).posts.first
    assert_equal "=?base64?#{Base64.strict_encode64('héllo')}?=", post[:headers]["Mcp-Name"]
  end

  # --- subscriptions/listen ---

  def test_listen_posts_subscriptions_listen_and_delivers_notifications
    chunks = [
      "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/subscriptions/acknowledged\",\"params\":{\"notifications\":{\"toolsListChanged\":true}}}\n\n",
      "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n"
    ]
    transport = fake_transport(FakeStreamableResponse.new(200, "text/event-stream", chunks))
    messages = []
    transport.on_message { |m| messages << m }
    transport.protocol_version = "2026-07-28"
    transport.start

    transport.listen(toolsListChanged: true)

    wait_until(timeout: 2) { messages.size >= 2 }
    assert_equal 2, messages.size
    assert_equal "notifications/subscriptions/acknowledged", messages.first.method
    assert_equal "notifications/tools/list_changed", messages.last.method

    post = transport.instance_variable_get(:@http).posts.first
    assert_equal "subscriptions/listen", post[:headers]["Mcp-Method"]
    body = JSON.parse(post[:body], symbolize_names: true)
    assert_equal "subscriptions/listen", body[:method]
    assert_equal true, body[:params][:notifications][:toolsListChanged]
  end

  # --- Client integration: x-mcp-header param mirroring (SEP-2243) ---

  def test_client_mirrors_x_mcp_header_params
    fake_client = FakeHTTPClient.new do |body, _headers|
      req = JSON.parse(body, symbolize_names: true)
      result = case req[:method]
               when "server/discover"
                 { protocolVersions: Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS,
                   capabilities: { tools: {} }, serverInfo: { name: "s", version: "1" } }
               when "tools/list"
                 { tools: [{ name: "execute_sql", description: "d",
                             inputSchema: { type: "object",
                                            properties: {
                                              region: { type: "string", :"x-mcp-header" => "Region" },
                                              query: { type: "string" }
                                            },
                                            required: ["region", "query"] } }] }
               when "tools/call"
                 { content: [{ type: "text", text: "ok" }], resultType: "complete" }
               end
      FakeStreamableResponse.new(200, "application/json",
                                 [JSON.generate({ jsonrpc: "2.0", id: req[:id], result: result })])
    end
    HTTPX.stubs(:with).returns(fake_client)

    transport = Ask::MCP::Transport::StreamableHTTP.new("http://localhost:8080/mcp")
    client = Ask::MCP::Client.new(transport)
    client.start
    assert client.initialized?

    client.tools
    client.call_tool("execute_sql", { region: "us-west1", query: "SELECT 1" })

    call_post = fake_client.posts.find { |p| p[:headers]["Mcp-Method"] == "tools/call" }
    refute_nil call_post, "expected a tools/call POST"
    assert_equal "us-west1", call_post[:headers]["Mcp-Param-Region"]
    refute call_post[:headers].key?("Mcp-Param-Query"), "unannotated params must not become headers"
    assert_equal "2026-07-28", call_post[:headers]["MCP-Protocol-Version"]
  end
end
