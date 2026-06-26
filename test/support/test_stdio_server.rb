#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "ostruct"

# Define test tools that quack like Ask::Tool
class EchoTestTool
  def name; "echo" end
  def description; "Echo back a message" end
  def params_schema
    { type: "object", properties: { message: { type: "string", description: "Message to echo" } }, required: ["message"] }
  end
  def call(args = {})
    OpenStruct.new(ok?: true, output: "Echo: #{args['message']}", error_message: nil, ok: true)
  end
end

class ReverseTestTool
  def name; "reverse" end
  def description; "Reverse a string" end
  def params_schema
    { type: "object", properties: { text: { type: "string", description: "Text to reverse" } }, required: ["text"] }
  end
  def call(args = {})
    OpenStruct.new(ok?: true, output: args['text'].to_s.reverse, error_message: nil, ok: true)
  end
end

class FailTestTool
  def name; "fail" end
  def description; "Always fails" end
  def params_schema; nil end
  def call(args = {})
    OpenStruct.new(ok?: false, output: nil, error_message: "FAIL: something broke", ok: false)
  end
end

class NoopTestTool
  def name; "noop" end
  def description; "Does nothing" end
  def params_schema; nil end
  def call(args = {})
    OpenStruct.new(ok?: true, output: "", error_message: nil, ok: true)
  end
end

class AddTestTool
  def name; "add" end
  def description; "Add two numbers" end
  def params_schema
    { type: "object", properties: { a: { type: "number" }, b: { type: "number" } }, required: ["a", "b"] }
  end
  def call(args = {})
    result = args["a"].to_i + args["b"].to_i
    OpenStruct.new(ok?: true, output: result.to_s, error_message: nil, ok: true)
  end
end

tools = [
  EchoTestTool.new,
  ReverseTestTool.new,
  FailTestTool.new,
  NoopTestTool.new,
  AddTestTool.new
]

server = Ask::MCP::Server::Stdio.new(
  name: "test-stdio-server",
  tools: tools,
  capabilities: { tools: {} },
  debug: ENV["DEBUG"] == "1"
)
server.start
