# frozen_string_literal: true

require_relative "../test_helper"
require "base64"
require "stringio"

# Exercises the stateless Streamable HTTP transport (2026-07-28) through its
# Rack interface: no network, no server process, no client.
class ServerHTTPTest < Minitest::Test
  STATELESS = Ask::MCP::LATEST_PROTOCOL_VERSION
  ERROR_CODES = Ask::MCP::Native::Messages::ErrorCodes
  PROTOCOL_VERSION_KEY = Ask::MCP::Native::Messages::Meta::PROTOCOL_VERSION_KEY
  SERVER_INFO_KEY = Ask::MCP::Native::Messages::Meta::SERVER_INFO_KEY

  # Duck-typed tools — the shape Adapters::ToolServer documents.
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

  class OtherTool
    def name
      "other"
    end

    def description
      "A second tool"
    end

    def params_schema
      { "type" => "object", "properties" => {}, "required" => [] }
    end

    def call(_args)
      "other"
    end
  end

  # A name that cannot travel as a plain header value. Base64 carries bytes and
  # knows nothing of encodings, so this is what catches a decoded value coming
  # back untagged and comparing unequal to the body's UTF-8 text.
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
    @app = Ask::MCP::Server.rack_app(name: "test-server", version: "9.9.9", tools: [EchoTool.new])
  end

  # -- server/discover ----------------------------------------------------

  def test_server_discover_advertises_versions_and_identity
    status, headers, body = post(stateless("server/discover"), mcp_method: "server/discover")

    assert_equal 200, status
    assert_equal "application/json", headers["Content-Type"]

    result = parse(body)[:result]

    assert_includes result[:protocolVersions], STATELESS
    assert_includes result[:protocolVersions], "2025-06-18"
    assert_equal "test-server", result[:serverInfo][:name]
    assert_equal "9.9.9", result[:serverInfo][:version]
  end

  def test_unsupported_protocol_version_lists_the_supported_versions
    status, _headers, body = post(stateless("server/discover"), mcp_method: "server/discover",
                                                                protocol_version: "1999-01-01")

    assert_equal 400, status

    error = parse(body)[:error]

    assert_equal ERROR_CODES::UNSUPPORTED_PROTOCOL_VERSION, error[:code]
    assert_includes error[:message], "1999-01-01"
    assert_includes error[:data][:supported], STATELESS
  end

  # -- tools/list ---------------------------------------------------------

  def test_tools_list_returns_definitions_with_cache_hints
    _status, _headers, body = post(stateless("tools/list"), mcp_method: "tools/list")
    result = parse(body)[:result]

    assert_equal "complete", result[:resultType]
    assert_equal 60_000, result[:ttlMs]
    assert_equal "private", result[:cacheScope]
    assert_equal(["echo"], result[:tools].map { |tool| tool[:name] })
    assert_equal "Echoes text back", result[:tools].first[:description]
  end

  def test_results_carry_the_server_identity_in_meta
    _status, _headers, body = post(stateless("tools/list"), mcp_method: "tools/list")
    meta = parse(body)[:result][:_meta]

    # `_meta` keys are namespaced strings on the wire and symbolized by the
    # JSON parser, so a reader looks them up in their parsed form.
    server_info = meta[SERVER_INFO_KEY.to_sym]

    assert_equal "test-server", server_info[:name]
    assert_equal "9.9.9", server_info[:version]
  end

  # -- tools/call ---------------------------------------------------------

  def test_tools_call_returns_the_tool_output
    request = stateless("tools/call", params: { name: "echo", arguments: { text: "hi" } })
    status, _headers, body = post(request, mcp_method: "tools/call", mcp_name: "echo")

    assert_equal 200, status

    result = parse(body)[:result]

    assert_equal "echo: hi", result[:content].first[:text]
    refute result[:isError]
  end

  def test_unknown_tool_returns_an_error_result
    request = stateless("tools/call", params: { name: "nope", arguments: {} })
    status, _headers, body = post(request, mcp_method: "tools/call", mcp_name: "nope")

    assert_equal 200, status

    result = parse(body)[:result]

    assert result[:isError]
    assert_includes result[:content].first[:text], "Tool not found: nope"
  end

  # -- required request headers (SEP-2243) --------------------------------

  def test_missing_mcp_method_header_is_a_header_mismatch
    status, _headers, body = post(stateless("tools/list"))

    assert_equal 400, status

    error = parse(body)[:error]

    assert_equal ERROR_CODES::HEADER_MISMATCH, error[:code]
    assert_includes error[:message], "Mcp-Method"
  end

  def test_mismatched_mcp_method_header_is_a_header_mismatch
    status, _headers, body = post(stateless("tools/list"), mcp_method: "tools/call")

    assert_equal 400, status
    assert_includes parse(body)[:error][:message], "does not match"
  end

  def test_missing_mcp_name_header_is_a_header_mismatch
    request = stateless("tools/call", params: { name: "echo", arguments: { text: "hi" } })
    status, _headers, body = post(request, mcp_method: "tools/call")

    assert_equal 400, status
    assert_includes parse(body)[:error][:message], "Mcp-Name"
  end

  def test_mismatched_mcp_name_header_is_a_header_mismatch
    request = stateless("tools/call", params: { name: "echo", arguments: { text: "hi" } })
    status, _headers, body = post(request, mcp_method: "tools/call", mcp_name: "other")

    assert_equal 400, status
    assert_includes parse(body)[:error][:message], "Mcp-Name"
  end

  def test_base64_encoded_mcp_name_header_is_decoded
    request = stateless("tools/call", params: { name: "echo", arguments: { text: "hi" } })
    encoded = "=?base64?#{Base64.strict_encode64('echo')}?="
    status, _headers, body = post(request, mcp_method: "tools/call", mcp_name: encoded)

    assert_equal 200, status
    assert_equal "echo: hi", parse(body)[:result][:content].first[:text]
  end

  def test_a_base64_name_decodes_to_the_bodys_utf8_text
    app = Ask::MCP::Server.rack_app(name: "accent", tools: [AccentedTool.new])
    request = stateless("tools/call", params: { name: "café", arguments: {} })
    encoded = "=?base64?#{Base64.strict_encode64('café')}?="
    status, _headers, body = app.call(env_for(request, mcp_method: "tools/call", mcp_name: encoded))

    assert_equal 200, status
    assert_equal "accented", parse(body)[:result][:content].first[:text]
  end

  def test_a_legal_param_header_is_accepted
    request = stateless("tools/call", params: { name: "echo", arguments: { text: "hi" } })
    env = env_for(request, mcp_method: "tools/call", mcp_name: "echo")
    env["HTTP_MCP_PARAM_REGION"] = "us-west1"
    status, = @app.call(env)

    assert_equal 200, status
  end

  def test_an_illegal_param_header_value_is_rejected
    request = stateless("tools/call", params: { name: "echo", arguments: { text: "hi" } })
    env = env_for(request, mcp_method: "tools/call", mcp_name: "echo")
    env["HTTP_MCP_PARAM_REGION"] = "us\u2014west1"
    status, _headers, body = @app.call(env)

    assert_equal 400, status

    error = parse(body)[:error]

    assert_equal ERROR_CODES::HEADER_MISMATCH, error[:code]
    assert_includes error[:message], "Mcp-Param-Region"
  end

  # -- protocol version agreement -----------------------------------------

  def test_missing_protocol_version_header_is_a_header_mismatch
    status, _headers, body = post(stateless("tools/list"), mcp_method: "tools/list",
                                                           protocol_version: nil)

    assert_equal 400, status
    assert_includes parse(body)[:error][:message], "MCP-Protocol-Version"
  end

  def test_protocol_version_header_must_match_the_body
    request = stateless("tools/list", version: "2025-11-25")
    status, _headers, body = post(request, mcp_method: "tools/list", protocol_version: STATELESS)

    assert_equal 400, status

    error = parse(body)[:error]

    assert_equal ERROR_CODES::HEADER_MISMATCH, error[:code]
    assert_includes error[:message], "does not match body value"
  end

  def test_a_request_without_meta_is_refused
    request = { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }
    status, _headers, body = post(request, mcp_method: "tools/list")

    assert_equal 400, status
    assert_includes parse(body)[:error][:message], PROTOCOL_VERSION_KEY
  end

  # -- request framing ----------------------------------------------------

  def test_a_notification_is_accepted_without_a_body
    request = { jsonrpc: "2.0", method: "notifications/initialized" }
    status, _headers, body = post(request)

    assert_equal 202, status
    assert_equal "", body.join
  end

  def test_get_is_method_not_allowed
    status, headers, body = post("", mcp_method: nil, http_method: "GET")

    assert_equal 405, status
    assert_equal "POST", headers["Allow"]
    assert_includes parse(body)[:error][:message], "GET"
  end

  def test_an_unimplemented_method_returns_not_found
    request = stateless("tools/nonexistent")
    status, _headers, body = post(request, mcp_method: "tools/nonexistent")

    assert_equal 404, status
    assert_equal ERROR_CODES::METHOD_NOT_FOUND, parse(body)[:error][:code]
  end

  def test_malformed_json_is_a_parse_error
    status, _headers, body = post("{not json", mcp_method: "tools/list")

    assert_equal 400, status
    assert_equal ERROR_CODES::PARSE_ERROR, parse(body)[:error][:code]
  end

  def test_an_empty_body_is_a_parse_error
    status, _headers, body = post("", mcp_method: "tools/list")

    assert_equal 400, status
    assert_equal ERROR_CODES::PARSE_ERROR, parse(body)[:error][:code]
  end

  def test_a_batched_body_is_rejected
    status, _headers, body = post([stateless("tools/list")], mcp_method: "tools/list")

    assert_equal 400, status
    assert_equal ERROR_CODES::INVALID_REQUEST, parse(body)[:error][:code]
  end

  # -- Origin validation --------------------------------------------------

  def test_an_untrusted_origin_is_forbidden
    env = env_for(stateless("tools/list"), mcp_method: "tools/list")
    env["HTTP_ORIGIN"] = "https://evil.example.com"
    status, _headers, body = @app.call(env)

    assert_equal 403, status
    assert_includes parse(body)[:error][:message], "Origin"
  end

  def test_an_allowed_origin_is_accepted
    app = Ask::MCP::Server.rack_app(
      name: "browser", tools: [EchoTool.new], allowed_origins: ["https://app.example.com"]
    )
    env = env_for(stateless("tools/list"), mcp_method: "tools/list")
    env["HTTP_ORIGIN"] = "https://app.example.com"
    status, = app.call(env)

    assert_equal 200, status
  end

  # -- multi-tenant wiring ------------------------------------------------

  def test_authentication_failure_answers_unauthorized
    app = Ask::MCP::Server.rack_app(
      name: "secure", tools: [EchoTool.new], authenticate: ->(_env) {}
    )
    status, headers, = app.call(env_for(stateless("tools/list"), mcp_method: "tools/list"))

    assert_equal 401, status
    assert_equal "Bearer", headers["WWW-Authenticate"]
  end

  def test_tools_are_resolved_per_request
    app = Ask::MCP::Server.rack_app(
      name: "tenant",
      authenticate: ->(env) { env["HTTP_X_TENANT"] },
      tools: ->(tenant) { tenant == "pro" ? [EchoTool.new, OtherTool.new] : [EchoTool.new] }
    )

    assert_equal %w[echo other], listed_tools(app, "pro")
    assert_equal %w[echo], listed_tools(app, "free")
  end

  def test_the_default_context_is_the_rack_env
    app = Ask::MCP::Server.rack_app(
      name: "ctx",
      tools: ->(env) { env["HTTP_X_TOKEN"] == "secret" ? [OtherTool.new] : [] }
    )

    assert_equal ["other"], listed_tools(app, "secret", header: "HTTP_X_TOKEN")
  end

  def test_rack_app_factory_returns_a_rack_application
    app = Ask::MCP::Server.rack_app(name: "factory", tools: [EchoTool.new])

    assert_respond_to app, :call
    assert_equal 200, app.call(env_for(stateless("tools/list"), mcp_method: "tools/list")).first
  end

  private

  def stateless(method, id: 1, params: {}, version: STATELESS)
    {
      jsonrpc: "2.0",
      id: id,
      method: method,
      params: params.merge(_meta: { PROTOCOL_VERSION_KEY => version })
    }
  end

  def post(body, **options)
    @app.call(env_for(body, **options))
  end

  def env_for(body, mcp_method: nil, mcp_name: nil, http_method: "POST",
              protocol_version: STATELESS)
    env = {
      "REQUEST_METHOD" => http_method,
      "PATH_INFO" => "/mcp",
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "rack.input" => StringIO.new(body.is_a?(String) ? body : JSON.generate(body))
    }
    env["HTTP_MCP_METHOD"] = mcp_method unless mcp_method.nil?
    env["HTTP_MCP_NAME"] = mcp_name unless mcp_name.nil?
    env["HTTP_MCP_PROTOCOL_VERSION"] = protocol_version unless protocol_version.nil?
    env
  end

  def parse(body)
    JSON.parse(body.join, symbolize_names: true)
  end

  def listed_tools(app, tenant, header: "HTTP_X_TENANT")
    env = env_for(stateless("tools/list"), mcp_method: "tools/list").merge(header => tenant)
    _status, _headers, body = app.call(env)
    parse(body)[:result][:tools].map { |tool| tool[:name] }
  end
end
