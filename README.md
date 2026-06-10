# ask-mcp

[![Gem Version](https://badge.fury.io/rb/ask-mcp.svg)](https://badge.fury.io/rb/ask-mcp)

Model Context Protocol (MCP) client for Ruby. Connect to MCP servers via
stdio, SSE, or Streamable HTTP transports. Discover tools, resources, and prompts.

MCP is the industry standard for LLM tool discovery — the same protocol used by
Claude Code, Codex, Cursor, and GitHub Copilot.

## Installation

```ruby
gem "ask-mcp"
```

## Quick Start

```ruby
require "ask/mcp"

# Connect to a local MCP server via stdio
client = Ask::MCP.from_stdio("npx", ["@modelcontextprotocol/server-filesystem", "/tmp"])
client.start

# List available tools
client.tools.each { |name, tool| puts "#{name}: #{tool.description}" }

# Call a tool
result = client.call_tool("read_file", path: "/tmp/test.txt")
puts result

# Clean up
client.stop
```

### Transports

```ruby
# stdio — local processes
Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])

# SSE — remote servers
Ask::MCP.from_sse("https://mcp.example.com/sse")

# Streamable HTTP — remote servers
Ask::MCP.from_http("https://mcp.example.com/mcp")
```

### With ask-agent

```ruby
# MCP tools become Ask::Tool instances automatically
client = Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])
client.start

client.tools.each do |name, mcp_tool|
  agent.register_tool(mcp_tool.to_ask_tool)
end
```

## Configuration

```ruby
Ask::MCP.configure do |c|
  c.default_timeout = 30
  c.auth_provider = ->(url) { Ask::Auth.lookup("MCP_TOKEN_#{url}") }
end
```

## Integration with ask-agent

See [ask-agent README](https://github.com/ask-rb/ask-agent) for full documentation
on using MCP tools with the agent loop.

## License

MIT
