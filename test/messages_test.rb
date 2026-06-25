# frozen_string_literal: true

require_relative "test_helper"

class MessagesTest < Minitest::Test
  def test_request_construction
    req = Ask::MCP::Native::Messages::Request.new(method: "tools/list", params: {}, id: 1)
    assert_equal "2.0", req.to_h[:jsonrpc]
    assert_equal 1, req.to_h[:id]
    assert_equal "tools/list", req.to_h[:method]
    assert_equal({}, req.to_h[:params])
  end

  def test_request_without_params
    req = Ask::MCP::Native::Messages::Request.new(method: "tools/list")
    h = req.to_h
    assert_equal "2.0", h[:jsonrpc]
    assert h.key?(:id)
    refute h.key?(:params)
  end

  def test_request_with_string_id
    req = Ask::MCP::Native::Messages::Request.new(method: "initialize", id: "custom-1")
    assert_equal "custom-1", req.to_h[:id]
  end

  def test_notification_construction
    notif = Ask::MCP::Native::Messages::Notification.new(method: "notifications/initialized")
    h = notif.to_h
    assert_equal "2.0", h[:jsonrpc]
    assert_equal "notifications/initialized", h[:method]
    refute h.key?(:id)
    refute h.key?(:params)
  end

  def test_notification_with_params
    notif = Ask::MCP::Native::Messages::Notification.new(method: "notifications/tools/list_changed", params: {})
    h = notif.to_h
    assert_equal({}, h[:params])
  end

  def test_success_response
    resp = Ask::MCP::Native::Messages::Response.new(id: 1, result: { tools: [{ name: "test" }] })
    assert resp.success?
    h = resp.to_h
    assert_equal "2.0", h[:jsonrpc]
    assert_equal 1, h[:id]
    assert_equal [{ name: "test" }], h[:result][:tools]
    refute h.key?(:error)
  end

  def test_error_response
    resp = Ask::MCP::Native::Messages::Response.new(id: 1, error: { code: -32601, message: "Method not found" })
    refute resp.success?
    h = resp.to_h
    assert_equal(-32601, h[:error][:code])
    assert_equal "Method not found", h[:error][:message]
    refute h.key?(:result)
  end

  def test_response_without_result
    resp = Ask::MCP::Native::Messages::Response.new(id: 1)
    assert resp.success?
    assert_equal({}, resp.to_h[:result])
  end

  def test_error_response_with_data
    resp = Ask::MCP::Native::Messages::Response.new(
      id: 1, error: { code: -32000, message: "Tool error", data: { tool: "test" } }
    )
    h = resp.to_h
    assert_equal({ tool: "test" }, h[:error][:data])
  end

  def test_parse_request
    json = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Request, msg
  end

  def test_parse_notification
    json = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Notification, msg
  end

  def test_parse_success_response
    json = '{"jsonrpc":"2.0","id":1,"result":{}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Response, msg
    assert msg.success?
  end

  def test_error_codes_constants
    assert_equal(-32700, Ask::MCP::Native::Messages::ErrorCodes::PARSE_ERROR)
    assert_equal(-32600, Ask::MCP::Native::Messages::ErrorCodes::INVALID_REQUEST)
    assert_equal(-32601, Ask::MCP::Native::Messages::ErrorCodes::METHOD_NOT_FOUND)
    assert_equal(-32602, Ask::MCP::Native::Messages::ErrorCodes::INVALID_PARAMS)
    assert_equal(-32603, Ask::MCP::Native::Messages::ErrorCodes::INTERNAL_ERROR)
    assert_equal(-32000, Ask::MCP::Native::Messages::ErrorCodes::TOOL_NOT_FOUND)
    assert_equal(-32001, Ask::MCP::Native::Messages::ErrorCodes::RESOURCE_NOT_FOUND)
    assert_equal(-32002, Ask::MCP::Native::Messages::ErrorCodes::PROMPT_NOT_FOUND)
  end

  def test_error_messages_defined
    codes = Ask::MCP::Native::Messages::ErrorCodes::ERROR_MESSAGES
    assert_equal "Parse error", codes[-32700]
    assert_equal "Tool not found", codes[-32000]
  end

  def test_serialize_request_to_json
    req = Ask::MCP::Native::Messages::Request.new(method: "ping", id: 1)
    json = req.to_json
    parsed = JSON.parse(json)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal 1, parsed["id"]
    assert_equal "ping", parsed["method"]
  end

  def test_serialize_response_to_json
    resp = Ask::MCP::Native::Messages::Response.new(id: 1, result: { status: "ok" })
    json = resp.to_json
    parsed = JSON.parse(json)
    assert_equal "ok", parsed["result"]["status"]
  end

  def test_serialize_notification_to_json
    notif = Ask::MCP::Native::Messages::Notification.new(method: "notifications/ping")
    json = notif.to_json
    parsed = JSON.parse(json)
    assert_equal "notifications/ping", parsed["method"]
    refute parsed.key?("id")
  end
end
