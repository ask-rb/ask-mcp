# ask-mcp

[![Gem Version](https://badge.fury.io/rb/ask-mcp.svg)](https://badge.fury.io/rb/ask-mcp)

**Model Context Protocol (MCP) client for Ruby.** Connect to MCP servers via
stdio, SSE, or Streamable HTTP transports. Discover tools, resources, and
prompts. Supports the full MCP protocol with OAuth 2.1 authentication.

MCP is the industry standard for LLM tool discovery — the same protocol used by
Claude Code, Codex, Cursor, and GitHub Copilot.

## Installation

```ruby
gem "ask-mcp"
```

Or add to your Gemfile:

```ruby
gem "ask-mcp", "~> 0.1.0"
```

## Quick Start

```ruby
require "ask/mcp"

# Connect to a local MCP server via stdio
client = Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
client.start

# List available tools
client.tools.each { |name, tool| puts "#{name}: #{tool.description}" }

# Call a tool
result = client.call_tool("read_file", path: "/tmp/test.txt")
puts result

# Clean up
client.stop
```


## Running as an MCP Server

`ask-mcp` can run as a standalone MCP server over stdio, exposing any
`Ask::Tool` instances to MCP-compatible clients (Codex Desktop, Claude Code, etc.).

```ruby
require "ask/mcp"
require "ask-tools-shell"
require "ask-web-search"

tools = Ask::Tools::Shell::TOOLS.map(&:new)
tools << Ask::Tools::WebSearch.new

Ask::MCP::Server.start_stdio(
  name: "my-server",
  tools: tools,
  capabilities: { tools: {} }
)
```

Configure your MCP client:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "ruby",
      "args": ["path/to/your/script.rb"]
    }
  }
}
```

For a production example, see [llm-proxy](https://github.com/ask-rb/llm-proxy)
which embeds the same server and adds rate limiting, auth, and monitoring.

## Transports

```ruby
# stdio — local processes
Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])

# SSE — remote servers with Server-Sent Events
Ask::MCP.from_sse("https://mcp.example.com/sse")

# Streamable HTTP — remote servers
Ask::MCP.from_http("https://mcp.example.com/mcp")
```

## API

### Client Lifecycle

```ruby
# Create a client with any transport
transport = Ask::MCP::Transport::Stdio.new("ruby", ["server.rb"])
client = Ask::MCP::Client.new(transport, timeout: 30)

# Start the session (sends initialize + receives capabilities)
client.start

# Use the client
client.tools       # => { "tool_name" => #<Ask::MCP::Tool> }
client.resources   # => { "resource_uri" => #<Ask::MCP::Resource> }
client.prompts     # => { "prompt_name" => #<Ask::MCP::Prompt> }
client.call_tool("tool_name", arg1: "value")
client.read_resource("file:///path")
client.get_prompt("prompt_name", arg1: "value")

# Stop the session
client.stop
```

### Tool, Resource, Prompt Objects

```ruby
# Tool
tool = Ask::MCP::Tool.new(
  name: "read_file",
  description: "Read a file from disk",
  input_schema: {
    type: "object",
    properties: { path: { type: "string" } },
    required: ["path"]
  }
)
tool.name         # => "read_file"
tool.description  # => "Read a file from disk"
tool.input_schema # => { type: "object", ... }

# Resource
resource = Ask::MCP::Resource.new(
  uri: "file:///tmp/test.txt",
  name: "Test File",
  mime_type: "text/plain"
)

# Prompt
prompt = Ask::MCP::Prompt.new(
  name: "greet",
  description: "Generate a greeting",
  arguments: [{ name: "name", description: "Name to greet", required: true }]
)
```

### Authentication

```ruby
# Token-based auth
token = Ask::MCP::Auth::Token.new("my-api-token")
headers = token.apply({})  # => { "Authorization" => "Bearer my-api-token" }

# OAuth 2.1
oauth = Ask::MCP::Auth::OAuth.new(
  client_id: "my-client",
  client_secret: "my-secret",
  token_url: "https://auth.example.com/token",
  scopes: ["mcp"]
)
oauth.authenticate!
headers = oauth.apply({})
```

### With ask-agent

```ruby
require "ask/mcp"

client = Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])
client.start

# Convert MCP tools to Ask::Tool instances for use with Ask::Agent
client.tools.each do |name, mcp_tool|
  agent.register_tool(mcp_tool.to_ask_tool)
end

# Or use the adapter directly
wrapped = Ask::MCP::Adapters::AskTool.wrap(client.tools)
wrapped.each { |name, adapter| agent.register_tool(adapter.to_ask_tool) }
```


## Architecture

```
ask-mcp/
├── lib/ask/mcp.rb                         # Entry point, factory methods
├── lib/ask/mcp/client.rb                  # MCP client (connect, call_tool, etc.)
├── lib/ask/mcp/server.rb                  # MCP server representation + Server.start_stdio entry point
├── lib/ask/mcp/server/stdio.rb            # MCP server stdio runtime (run as server)
├── lib/ask/mcp/tool.rb                    # MCP tool representation
├── lib/ask/mcp/resource.rb                # MCP resource representation
├── lib/ask/mcp/prompt.rb                  # MCP prompt representation
├── lib/ask/mcp/native/messages.rb         # JSON-RPC message layer
├── lib/ask/mcp/transport/
│   ├── stdio.rb                           # stdio transport (client direction)
│   ├── sse.rb                             # Server-Sent Events transport
│   └── streamable_http.rb                 # Streamable HTTP transport
├── lib/ask/mcp/auth/
│   ├── oauth.rb                           # OAuth 2.1 for MCP
│   └── token.rb                           # Token-based auth
└── lib/ask/mcp/adapters/
    ├── ask_tool.rb                        # MCP::Tool → Ask::Tool adapter
    └── ask_tool_server.rb                 # Ask::Tool → MCP server adapter (reverse)
```
## Development

```bash
# Run tests
bundle exec rake test

# Run specific tests
bundle exec ruby -Itest test/messages_test.rb
bundle exec ruby -Itest test/stdio_integration_test.rb
```

## License

MIT

## Authentication

See the [Auth Setup Guide](docs/auth-setup.md) for detailed documentation on
token-based and OAuth 2.1 authentication, including ask-auth integration.
