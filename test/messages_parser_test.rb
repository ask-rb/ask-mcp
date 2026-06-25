# frozen_string_literal: true

require_relative "test_helper"

class MessagesParserTest < Minitest::Test
  def test_parse_success_response
    json = '{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Response, msg
    assert msg.success?
    assert_equal 1, msg.id
  end

  def test_parse_error_response
    json = '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Response, msg
    refute msg.success?
    assert_equal(-32601, msg.error[:code])
  end

  def test_parse_request
    json = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Request, msg
    assert_equal "tools/list", msg.method
    assert_equal({}, msg.params)
  end

  def test_parse_request_without_params
    json = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Request, msg
    assert_nil msg.params
  end

  def test_parse_notification
    json = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Notification, msg
    assert_equal "notifications/initialized", msg.method
  end

  def test_parse_notification_with_params
    json = '{"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}'
    msg = Ask::MCP::Native::Messages::Parser.parse(json)
    assert_instance_of Ask::MCP::Native::Messages::Notification, msg
    assert_equal({}, msg.params)
  end

  def test_parse_invalid_json
    assert_raises(JSON::ParserError) { Ask::MCP::Native::Messages::Parser.parse("not json") }
  end

  def test_parse_response_bang
    json = '{"jsonrpc":"2.0","id":1,"result":{}}'
    msg = Ask::MCP::Native::Messages::Parser.parse_response(json)
    assert_instance_of Ask::MCP::Native::Messages::Response, msg
  end

  def test_parse_response_bang_raises_on_wrong_type
    json = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    assert_raises(Ask::MCP::ProtocolError) { Ask::MCP::Native::Messages::Parser.parse_response(json) }
  end

  def test_parse_request_bang
    json = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    msg = Ask::MCP::Native::Messages::Parser.parse_request(json)
    assert_instance_of Ask::MCP::Native::Messages::Request, msg
  end

  def test_parse_request_bang_raises_on_wrong_type
    json = '{"jsonrpc":"2.0","id":1,"result":{}}'
    assert_raises(Ask::MCP::ProtocolError) { Ask::MCP::Native::Messages::Parser.parse_request(json) }
  end

  def test_parse_unknown_structure
    result = Ask::MCP::Native::Messages::Parser.parse('{"foo":"bar"}')
    assert_instance_of Hash, result
    assert_equal "bar", result[:foo]
  end

  def test_error_codes_defined
    assert_equal(-32700, Ask::MCP::Native::Messages::ErrorCodes::PARSE_ERROR)
    assert_equal(-32601, Ask::MCP::Native::Messages::ErrorCodes::METHOD_NOT_FOUND)
    assert_equal(-32602, Ask::MCP::Native::Messages::ErrorCodes::INVALID_PARAMS)
    assert_equal(-32000, Ask::MCP::Native::Messages::ErrorCodes::TOOL_NOT_FOUND)
  end
end
