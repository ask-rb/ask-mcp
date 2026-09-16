# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/rack_http_server"

# Drives the HTTP transport with the real client over a real socket. The
# env-level tests prove the server's own logic; this proves the two sides agree
# on the wire — the mirrored request headers, the base64 sentinel form for
# names that are not plain ASCII, and the stateless `_meta` envelope.
class ServerHTTPInteropTest < Minitest::Test
  class EchoTool
    def name
      "echo"
    end

    def description
      "Echoes text back"
    end

    def params_schema
      { "type" => "object",
        "properties" => { "text" => { "type" => "string" } },
        "required" => ["text"] }
    end

    def call(args)
      "echo: #{args['text']}"
    end
  end

  # A name that cannot travel as a plain header value, so the client encodes
  # it and the server has to decode it before comparing.
  class AccentedTool
    def name
      "café"
    end

    def description
      "A tool whose name is not plain ASCII"
    end

    def params_schema
      { "type" => "object", "properties" => {}, "required" => [] }
    end

    def call(_args)
      "accented"
    end
  end

  def setup
    @server = RackHTTPServer.new(
      Ask::MCP::Server.rack_app(name: "interop", version: "1.2.3",
                                tools: [EchoTool.new, AccentedTool.new])
    )
    @client = Ask::MCP::Client.new(Ask::MCP::Transport::StreamableHTTP.new(@server.url), timeout: 5)
    @client.start
  end

  def teardown
    @client&.stop
    @server&.shutdown
  end

  def test_negotiates_the_stateless_revision
    assert_predicate @client, :initialized?
    assert_equal Ask::MCP::LATEST_PROTOCOL_VERSION,
                 @client.instance_variable_get(:@protocol_version)
  end

  def test_lists_tools_over_http
    tools = @client.tools

    assert tools.key?("echo"), "expected the echo tool, got #{tools.keys.inspect}"

    schema = tools["echo"].input_schema

    assert_includes schema[:properties].keys.map(&:to_s), "text"
  end

  def test_calls_a_tool_over_http
    content = @client.call_tool("echo", { text: "hi" })

    assert_equal "echo: hi", text_of(content)
  end

  def test_calls_a_tool_whose_name_needs_the_base64_sentinel
    content = @client.call_tool("café", {})

    assert_equal "accented", text_of(content)
  end

  def test_unknown_tool_surfaces_the_server_message
    content = @client.call_tool("nope", {})

    assert_includes text_of(content), "Tool not found: nope"
  end

  private

  def text_of(content)
    content.is_a?(Array) ? content.first[:text] : content.to_s
  end
end
