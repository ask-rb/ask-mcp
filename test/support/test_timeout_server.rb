#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "ostruct"

class SlowTestTool
  def name; "slow" end
  def description; "Sleeps for N seconds" end
  def params_schema
    { type: "object", properties: { seconds: { type: "number" } }, required: ["seconds"] }
  end
  def call(args = {})
    sleep(args["seconds"].to_f)
    OpenStruct.new(ok?: true, output: "done", error_message: nil, ok: true)
  end
end

Ask::MCP::Server::Stdio.new(
  name: "timeout-test-server",
  tools: [SlowTestTool.new],
  capabilities: { tools: {} },
  debug: ENV["DEBUG"] == "1",
  tool_timeout: 1
).start
