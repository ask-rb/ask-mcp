#!/usr/bin/env ruby
# frozen_string_literal: true

# A mock MCP server for integration testing.
# Responds to JSON-RPC 2.0 messages over stdio.

require "json"

$stdout.sync = true

def send_response(id, result = nil, error = nil)
  msg = { jsonrpc: "2.0", id: id }
  if error
    msg[:error] = error
  else
    msg[:result] = result || {}
  end
  $stdout.puts msg.to_json
end

# Read and process JSON-RPC messages from stdin
handler = ->(request) {
  method = request[:method]
  id = request[:id]
  params = request[:params] || {}

  case method
  when "initialize"
    send_response(id, {
      protocolVersion: "0.1.0",
      capabilities: {
        tools: {},
        resources: {},
        prompts: {}
      },
      serverInfo: {
        name: "mock-mcp-server",
        version: "0.1.0"
      }
    })

  when "notifications/initialized"
    nil

  when "tools/list"
    send_response(id, {
      tools: [
        {
          name: "echo",
          description: "Echo back a message",
          inputSchema: {
            type: "object",
            properties: {
              message: { type: "string", description: "Message to echo" }
            },
            required: ["message"]
          }
        },
        {
          name: "add",
          description: "Add two numbers",
          inputSchema: {
            type: "object",
            properties: {
              a: { type: "number", description: "First number" },
              b: { type: "number", description: "Second number" }
            },
            required: ["a", "b"]
          }
        }
      ]
    })

  when "tools/call"
    tool_name = params[:name]
    args = params[:arguments] || {}

    case tool_name
    when "echo"
      send_response(id, {
        content: [
          { type: "text", text: "Echo: #{args[:message]}" }
        ]
      })
    when "add"
      result = args[:a].to_i + args[:b].to_i
      send_response(id, {
        content: [
          { type: "text", text: result.to_s }
        ]
      })
    else
      send_response(id, nil, { code: -32601, message: "Tool not found: #{tool_name}" })
    end

  when "resources/list"
    send_response(id, {
      resources: [
        {
          uri: "greeting://world",
          name: "World Greeting",
          description: "A greeting for the world",
          mimeType: "text/plain"
        }
      ]
    })

  when "resources/read"
    send_response(id, {
      contents: [
        { uri: params[:uri], text: "Hello, World!" }
      ]
    })

  when "prompts/list"
    send_response(id, {
      prompts: [
        {
          name: "greet",
          description: "Generate a greeting",
          arguments: [
            { name: "name", description: "Name to greet", required: true }
          ]
        }
      ]
    })

  when "prompts/get"
    send_response(id, {
      messages: [
        { role: "user", content: { type: "text", text: "Greet #{params.dig(:arguments, :name)}" } }
      ]
    })

  else
    send_response(id, nil, { code: -32601, message: "Method not found: #{method}" })
  end
}

# Main read loop
buffer = String.new
while (char = $stdin.getc)
  buffer << char
  if buffer.end_with?("\n")
    line = buffer.strip
    buffer = String.new
    next if line.empty?

    begin
      request = JSON.parse(line, symbolize_names: true)
      handler.call(request)
    rescue JSON::ParserError => e
      send_response(request&.dig(:id), nil, { code: -32700, message: "Parse error: #{e.message}" })
    end
  end
end
