# frozen_string_literal: true

require_relative "test_helper"

class TraceContextTest < Minitest::Test
  def test_from_headers_case_insensitive
    headers = { "Traceparent" => "00-abc-01", "TRACESTATE" => "vendor=1", "Baggage" => "user=7" }
    ctx = Ask::MCP::TraceContext.from_headers(headers)
    assert_equal "00-abc-01", ctx["traceparent"]
    assert_equal "vendor=1", ctx["tracestate"]
    assert_equal "user=7", ctx["baggage"]
  end

  def test_from_headers_accepts_rack_env_convention
    rack_env = {
      "HTTP_TRACEPARENT" => "00-abc-01",
      "HTTP_TRACESTATE" => "vendor=1",
      "HTTP_BAGGAGE" => "user=7",
      "REQUEST_METHOD" => "POST"
    }
    ctx = Ask::MCP::TraceContext.from_headers(rack_env)
    assert_equal "00-abc-01", ctx["traceparent"]
    assert_equal "vendor=1", ctx["tracestate"]
    assert_equal "user=7", ctx["baggage"]
    refute ctx.key?("request_method"), "unrelated headers must be ignored"
  end

  def test_from_headers_with_string_keys
    ctx = Ask::MCP::TraceContext.from_headers({ "traceparent" => "00-abc-01" })
    assert_equal "00-abc-01", ctx["traceparent"]
  end

  def test_from_meta_with_symbol_and_string_keys
    symbolized = { traceparent: "00-abc-01" }
    assert_equal "00-abc-01", Ask::MCP::TraceContext.from_meta(symbolized)["traceparent"]

    stringified = { "tracestate" => "vendor=1" }
    assert_equal "vendor=1", Ask::MCP::TraceContext.from_meta(stringified)["tracestate"]
  end

  def test_from_meta_empty
    assert_equal({}, Ask::MCP::TraceContext.from_meta(nil))
    assert_equal({}, Ask::MCP::TraceContext.from_meta({}))
  end
end
