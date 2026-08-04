#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "ostruct"
require "json"

class EchoTestTool
  def name; "echo" end
  def description; "Echo back a message" end
  # 2025-11-25: optional display metadata (title + icons, SEP-973)
  def title; "Echo Tool" end
  def icons
    [{ src: "https://example.com/echo-icon.png", mimeType: "image/png", sizes: ["48x48"] }]
  end
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

class SlowTestTool
  def name; "slow" end
  def description; "Sleeps for N seconds" end
  def params_schema
    { type: "object", properties: { seconds: { type: "number", description: "Seconds to sleep" } }, required: ["seconds"] }
  end
  def call(args = {})
    secs = args["seconds"].to_f
    sleep(secs)
    OpenStruct.new(ok?: true, output: "slept #{secs}s", error_message: nil, ok: true)
  end
end

class MultilineTestTool
  def name; "multiline" end
  def description; "Returns multiline text" end
  def params_schema; nil end
  def call(args = {})
    OpenStruct.new(
      ok?: true,
      output: "line one\nline two\nline three\n\nspecial chars: \u2603 \u2728 \nend",
      error_message: nil,
      ok: true
    )
  end
end

class GreetingResource
  def uri; "greeting://world" end
  def name; "World Greeting" end
  def description; "A greeting for the world" end
  def mime_type; "text/plain" end
  # 2025-11-25: optional display metadata
  def title; "World Greeting" end
  def icons
    [{ src: "https://example.com/world-icon.png", mimeType: "image/png", sizes: ["48x48"] }]
  end
  def content
    [{ uri: uri, mimeType: mime_type, text: "Hello, World!" }]
  end
end

class NoteResource
  def uri; "note://scratch" end
  def name; "Scratch Note" end
  def description; "An empty scratch note" end
  def mime_type; "text/plain" end
  def content
    [{ uri: uri, mimeType: mime_type, text: "" }]
  end
end

class FileTemplate
  def uri_template; "file:///{path}" end
  def name; "Project Files" end
  def title; "Project Files" end
  def mime_type; "application/octet-stream" end
  def to_h
    h = { uriTemplate: uri_template, name: name }
    h[:title] = title
    h[:mimeType] = mime_type
    h
  end
end

class GreetPrompt
  def name; "greet" end
  def description; "Generate a greeting" end
  def arguments
    [{ name: "name", description: "Name to greet", required: true }]
  end
  def messages
    [{ role: "user", content: { type: "text", text: "Greet the user" } }]
  end
end

tools = [
  EchoTestTool.new,
  ReverseTestTool.new,
  FailTestTool.new,
  NoopTestTool.new,
  AddTestTool.new,
  SlowTestTool.new,
  MultilineTestTool.new
]

server = Ask::MCP::Server::Stdio.new(
  name: "test-stdio-server",
  tools: tools,
  resources: {
    "greeting://world" => GreetingResource.new,
    "note://scratch" => NoteResource.new
  },
  prompts: {
    "greet" => GreetPrompt.new
  },
  resource_templates: {
    "file:///{path}" => FileTemplate.new
  },
  capabilities: { tools: {}, resources: {}, prompts: {} },
  debug: ENV["DEBUG"] == "1"
)
server.start
