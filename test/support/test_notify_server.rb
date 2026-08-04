#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "ostruct"
require "json"

# A server whose tools emit list_changed notifications on demand, so tests
# can verify server→client change notifications deterministically (the
# notification is written before the tool response, on the same thread).
server = nil

tools = %w[tools resources prompts].map do |kind|
  tool = Object.new
  tool.define_singleton_method(:name) { "notify_#{kind}" }
  tool.define_singleton_method(:description) { "Emits notifications/#{kind}/list_changed" }
  tool.define_singleton_method(:params_schema) { nil }
  tool.define_singleton_method(:call) do |_args|
    server.__send__("notify_#{kind}_list_changed")
    OpenStruct.new(ok?: true, output: "notified #{kind}", error_message: nil, ok: true)
  end
  tool
end

server = Ask::MCP::Server::Stdio.new(
  name: "notify-server",
  tools: tools,
  capabilities: { tools: {} }
)
server.start
