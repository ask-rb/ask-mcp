#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "ostruct"

tool = Class.new do
  define_method(:name) { "ping" }
  define_method(:description) { "Ping" }
  define_method(:params_schema) { nil }
  define_method(:call) { |args| OpenStruct.new(ok?: true, output: "pong", error_message: nil, ok: true) }
end

Ask::MCP::Server.start_stdio(name: "start-stdio-test", tools: [tool.new])
