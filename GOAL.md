# ask-mcp — MCP Client for Ruby

## Purpose

A full Model Context Protocol (MCP) client for Ruby. Connect to MCP servers
via stdio, SSE, or Streamable HTTP transports. Discover tools, resources, and
prompts. Optionally convert MCP tools to Ask::Tool instances for use with
ask-agent.

MCP is the industry standard protocol for LLM tool/resource discovery —
used by Claude Code, Codex, Cursor, and GitHub Copilot.

## Dependencies

- **Runtime:** `httpx ~> 1.4`, `json-schema ~> 5.0`
- **No ask-rb dependencies** in the core client. Optional adapter for
  Ask::Tool conversion.
- **Build/test:** minitest, mocha, rake

## How This Improves on ruby_llm-mcp

| Old Gem | Our Gem |
|---|---|
| Depends on ruby_llm (entire provider stack) | Zero ask-rb deps for core MCP client |
| RubyLLM::Chat integration tightly coupled | Pure MCP protocol implementation |
| OAuth via RubyLLM's auth | Uses ask-auth or any custom auth provider |
| Tool conversion baked into ruby_llm types | MCP tools → Ask::Tool adapter (optional) |
| Complex adapter layer (mcp_sdk vs native) | Single native implementation, clean |
| ~80 files, some redundant | ~40 files, focused and modular |

## Architecture

```
ask-mcp/
├── lib/ask/mcp.rb                     # Entry point, factory methods
├── lib/ask/mcp/client.rb              # MCP client (connect, call_tool, etc.)
├── lib/ask/mcp/server.rb             # MCP server discovery
├── lib/ask/mcp/tool.rb               # MCP tool representation
├── lib/ask/mcp/resource.rb           # MCP resource representation
├── lib/ask/mcp/prompt.rb             # MCP prompt representation
├── lib/ask/mcp/transport/
│   ├── stdio.rb                       # stdio transport
│   ├── sse.rb                         # Server-Sent Events transport
│   └── streamable_http.rb             # Streamable HTTP transport
├── lib/ask/mcp/auth/
│   ├── oauth.rb                       # OAuth 2.1 for MCP
│   └── token.rb                       # Token-based auth
└── lib/ask/mcp/adapters/
    └── ask_tool.rb                    # MCP::Tool → Ask::Tool adapter
```

## Implementation Steps

### 1. Core Protocol (`lib/ask/mcp/native/`)

Implement the JSON-RPC message layer:
- Requests, notifications, responses
- Protocol version negotiation
- Capability discovery
- Error handling (JSON-RPC error codes)

### 2. Transports

**stdio:** Connect to local processes via stdin/stdout pipes.
- `Ask::MCP::Transport::Stdio.new(command, args, options)`
- Start process, establish JSON-RPC over stdio
- Handle process lifecycle (start, stop, restart)

**SSE:** Connect to remote servers via Server-Sent Events.
- `Ask::MCP::Transport::SSE.new(url, options)`
- HTTP GET for SSE stream, POST for responses
- Reconnection logic

**Streamable HTTP:** Connect via HTTP streaming.
- `Ask::MCP::Transport::StreamableHTTP.new(url, options)`
- Bidirectional HTTP stream
- Support for HTTP/2 streaming

### 3. Client

`Ask::MCP::Client` wraps a transport and provides the MCP API:
- `start` / `stop` — session lifecycle
- `tools` — list discovered tools
- `resources` — list discovered resources
- `prompts` — list discovered prompts
- `call_tool(name, args)` — execute a tool
- `read_resource(uri)` — read a resource
- `get_prompt(name, args)` — get a prompt

### 4. Auth

- **Token:** Simple Bearer token auth
- **OAuth 2.1:** Authorization code flow + client credentials flow
  - Dynamic client registration
  - Token refresh
  - Optional ask-auth integration

### 5. Ask::Tool Adapter (optional, loaded on demand)

```ruby
# When ask-tools is available, wrap MCP tools as Ask::Tool instances
tool = Ask::MCP::Tool.new(name: "read_file", description: "Read a file", 
                          input_schema: { type: "object", properties: { path: { type: "string" } } })
ask_tool = Ask::MCP::Adapters::AskTool.new(tool)
# Now it works with Ask::Agent, Ask::Tools, etc.
```

### 6. Tests

- Protocol: JSON-RPC message construction, parsing, error codes
- Transports: stdio process spawning, SSE reconnection, HTTP streaming
- Client: tool discovery, tool calling, resource reading
- Auth: token flow, OAuth flow, token refresh
- Adapter: MCP tool → Ask::Tool conversion
- Integration: connect to a real MCP server and call a tool

### 7. Documentation

- README: quick start for each transport, examples
- Auth setup guide
- Adapter usage with ask-agent
- Migration guide from ruby_llm-mcp

## Release Notes

v0.1.0: Core MCP client + stdio transport + tool discovery + Ask::Tool adapter
v0.2.0: SSE + Streamable HTTP transports
v0.3.0: OAuth 2.1 auth + full protocol coverage
