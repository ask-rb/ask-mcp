# frozen_string_literal: true

require_relative "test_helper"

class MessagesTest < Minitest::Test
  def test_request_construction
    req = Ask::MCP::Native::Messages::Request.new(
      method: "tools/list",
      params: {},
      id: 1
    )
    assert_equal "2.0", req.to_h[:jsonrpc]
    assert_equal 1, req.to_h[:id]
    assert_equal "tools/list", req.to_h[:method]
    assert_equal({}, req.to_h[:params])
  end

  def test_request_without_params
    req = Ask::MCP::Native::Messages::Request.new(method: "tools/list")
    h = req.to_h
    assert_equal "2.0", h[:jsonrpc]
    assert_equal "tools/list", h[:method]
    assert req.to_h.key?(:id)
    refute h.key?(:params)
  end

  def test_notification_construction
    notif = Ask::MCP::Native::Messages::Notification.new(
      method: "notifications/initialized"
    )
    h = notif.to_h
    assert_equal "2.0", h[:jsonrpc]
    assert_equal "notifications/initialized", h[:method]
    refute h.key?(:id)
    refute h.key?(:params)
  end

  def test_success_response
    resp = Ask::MCP::Native::Messages::Response.new(
      id: 1,
      result: { tools: [{ name: "test" }] }
    )
    assert resp.success?
    h = resp.to_h
    assert_equal "2.0", h[:jsonrpc]
    assert_equal 1, h[:id]
    assert_equal [{ name: "test" }], h[:result][:tools]
    refute h.key?(:error)
  end

  def test_error_response
    resp = Ask::MCP::Native::Messages::Response.new(
      id: 1,
      error: { code: -32601, message: "Method not found" }
    )
    refute resp.success?
    h = resp.to_h
    assert_equal(-32601, h[:error][:code])
    assert_equal "Method not found", h[:error][:message]
    refute h.key?(:result)
  end

  def test_parse_request
    json = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Request, msg
    assert_equal "tools/list", msg.method
    assert_equal 1, msg.id
  end

  def test_parse_notification
    json = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Notification, msg
    assert_equal "notifications/initialized", msg.method
  end

  def test_parse_success_response
    json = '{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Response, msg
    assert msg.success?
    assert_equal({ tools: [] }, msg.result)
  end

  def test_parse_error_response
    json = '{"jsonrpc":"2.0","id":1,"error":{"code":-32700,"message":"Parse error"}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Response, msg
    refute msg.success?
    assert_equal(-32700, msg.error[:code])
  end

  def test_request_to_json
    req = Ask::MCP::Native::Messages::Request.new(method: "ping", id: 5)
    parsed = JSON.parse(req.to_json)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal 5, parsed["id"]
    assert_equal "ping", parsed["method"]
  end

  def test_error_codes_defined
    assert_equal(-32700, Ask::MCP::Native::Messages::ErrorCodes::PARSE_ERROR)
    assert_equal(-32603, Ask::MCP::Native::Messages::ErrorCodes::INTERNAL_ERROR)
    assert_equal(-32000, Ask::MCP::Native::Messages::ErrorCodes::TOOL_NOT_FOUND)
    assert_equal(-32004, Ask::MCP::Native::Messages::ErrorCodes::CONNECTION_ERROR)
  end
end
