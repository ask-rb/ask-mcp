# ask-mcp

[![Gem Version](https://badge.fury.io/rb/ask-mcp.svg)](https://badge.fury.io/rb/ask-mcp)

Model Context Protocol (MCP) client and server for Ruby. Connect to MCP
servers over stdio, SSE, or Streamable HTTP transports, or run as an MCP
server to expose your own tools to any MCP client (Claude Code, Codex, Cursor,
GitHub Copilot). No framework lock-in: implement a couple of duck-typed
methods and you are done.

## Installation

```ruby
gem "ask-mcp"
```

## Quick Start: Client

Connect to any MCP server and call its tools:

```ruby
require "ask/mcp"

client = Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
client.start

client.tools.each { |name, tool| puts "#{name}: #{tool.description}" }

result = client.call_tool("read_file", path: "/tmp/test.txt")
puts result

client.stop
```

## Quick Start: Server

Run as a standalone MCP server. Any object that responds to `name`,
`description`, `params_schema`, and `call(args)` works:

```ruby
require "ask/mcp"

class Greeter
  def name; "greet" end
  def description; "Greets someone by name" end
  def params_schema
    { type: "object", properties: { "name" => { "type" => "string" } }, required: ["name"] }
  end
  def call(args = {})
    "Hello, #{args['name']}!"
  end
end

# Blocking: runs until stdin closes
Ask::MCP::Server.start_stdio(name: "my-server", tools: [Greeter.new])
```

Point any MCP client at it:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "ruby",
      "args": ["/path/to/your/server.rb"]
    }
  }
}
```

The result of `call(args)` may be a plain value, or an object responding to
`ok?` and `output` / `error_message` (for example an `OpenStruct`). The server
wraps results into MCP's `content` array format automatically.

## Transports

```ruby
# stdio: local processes
Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])

# SSE: remote servers with Server-Sent Events
Ask::MCP.from_sse("https://mcp.example.com/sse")

# Streamable HTTP: remote servers
Ask::MCP.from_http("https://mcp.example.com/mcp")
```

Each factory returns a client backed by `Ask::MCP::Transport::Stdio`,
`Ask::MCP::Transport::SSE`, or `Ask::MCP::Transport::StreamableHTTP`.

## Essential API

| Entry point | Purpose |
|---|---|
| `client.start` / `client.stop` | Start the session (initialize + capabilities) and shut it down |
| `client.tools` / `client.resources` / `client.prompts` | Indexed lists exposed by the server |
| `client.call_tool(name, args)` | Invoke a tool; also `read_resource(uri)` and `get_prompt(name, args)` |
| `Ask::MCP::Adapters::AskTool.wrap(tools_hash)` | Adapter from MCP tools to `Ask::Tool` instances for ask-agent |
| `Ask::MCP::Adapters::ToolServer` | Adapter from duck-typed tools to MCP server tools |
| `Ask::MCP::Auth::Token.new(token)` | Token-based auth (`apply(headers)`) |
| `Ask::MCP::Auth::OAuth.new(client_id:, token_url:, ...)` | OAuth for MCP (`authenticate!`, `apply(headers)`) |

### With ask-agent

```ruby
client = Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])
client.start

wrapped = Ask::MCP::Adapters::AskTool.wrap(client.tools)
wrapped.each { |name, adapter| agent.register_tool(adapter.to_ask_tool) }
```

Expose `Ask::Tool` subclasses as an MCP server with `Ask::MCP::Server.start_stdio(name:, tools:, capabilities: { tools: {} })`; the `ToolServer` adapter handles them.

## Full documentation

The full ask-rb documentation lives at https://ask-rb.github.io/ask-docs.
https://ask-rb.github.io/ask-docs/core/mcp covers ask-mcp in depth, including
tool, resource, and prompt objects, protocol details, and auth. See also the
[Auth Setup Guide](docs/auth-setup.md) for token and OAuth 2.1 setup with
ask-auth. API reference: https://ask-rb.github.io/ask-docs/reference/api.

## Development

bundle install
bundle exec rake test

## License

MIT
