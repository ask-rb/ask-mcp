# ask-mcp

[![Gem Version](https://badge.fury.io/rb/ask-mcp.svg)](https://badge.fury.io/rb/ask-mcp)

Model Context Protocol (MCP) client and server for Ruby. Connect to MCP
servers over stdio, SSE, or Streamable HTTP transports, or run as an MCP
server to expose your own tools to any MCP client (Claude Code, Codex, Cursor,
GitHub Copilot). No framework lock-in: implement a couple of duck-typed
methods and you are done.

Speaks the protocol **dual-mode**: legacy `initialize`-handshake revisions
(`2025-06-18`, `2025-11-25`) and the stateless `2026-07-28` revision
(`server/discover`, per-request `_meta`, MRTR). Clients negotiate
automatically; servers answer both eras on one connection. See
[docs/SPEC_COMPLIANCE.md](docs/SPEC_COMPLIANCE.md) for the full status across
all three revisions.

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

`start` probes `server/discover` first: a `2026-07-28` server is used
statelessly (no handshake; every request carries `_meta`), and older servers
fall back to the `initialize` handshake automatically.

### Server-initiated requests (elicitation, sampling)

Servers can ask the client for input — user answers (elicitation) or LLM
completions (sampling). Register handlers; the client answers the server and,
in the stateless revision, completes the request via
[MRTR](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr):

```ruby
client.on_elicitation { |params| { message: "42" } }
client.on_sampling do |params|
  # params includes `tools` / `toolChoice` when the server offers tool calling
  { role: "assistant", content: { type: "text", text: "Paris" } }
end
# any on_request("method") { |params| ... } works for custom server requests
```

Declare support so servers know they can ask:
`Ask::MCP::Client.new(transport, client_capabilities: { elicitation: {}, sampling: {} })`.

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
Ask::MCP::Server.start_stdio(
  name: "my-server",
  tools: [Greeter.new],
  resources: { "greeting://world" => GreetingResource.new },   # uri → object
  prompts: { "greet" => GreetPrompt.new },                    # name → object
  resource_templates: { "file:///{path}" => FileTemplate.new }
)
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
wraps results into MCP's `content` array format automatically. Resources and
prompts are duck-typed: objects with `to_h` are serialized directly, otherwise
accessors (`title`, `description`, `mime_type`, `icons`, `arguments`) are
collected; `resources/read` and `prompts/get` pull contents from `content` /
`read` / `messages`.

When your tool/resource/prompt sets change at runtime, tell clients:

```ruby
server.notify_tools_list_changed
server.notify_resources_list_changed
server.notify_prompts_list_changed
```

## Transports

```ruby
# stdio: local processes
Ask::MCP.from_stdio("npx", ["-y", "@modelcontextprotocol/server-github"])

# SSE: remote servers with Server-Sent Events (deprecated upstream — prefer Streamable HTTP)
Ask::MCP.from_sse("https://mcp.example.com/sse")

# Streamable HTTP: remote servers
Ask::MCP.from_http("https://mcp.example.com/mcp")
```

Each factory returns a client backed by `Ask::MCP::Transport::Stdio`,
`Ask::MCP::Transport::SSE`, or `Ask::MCP::Transport::StreamableHTTP`.

The Streamable HTTP transport implements the `2026-07-28` shape: one POST per
message with `MCP-Protocol-Version` / `Mcp-Method` / `Mcp-Name` headers
(Base64-sentinel value encoding), per-response JSON-or-SSE handling, and
`subscriptions/listen` long-lived notification streams:

```ruby
client.listen(toolsListChanged: true, resourceSubscriptions: ["file:///x"])
```

Tool parameters annotated with `x-mcp-header` in the server's `inputSchema`
are mirrored into `Mcp-Param-{Name}` headers; tool definitions with invalid
annotations are excluded from `tools/list` on HTTP transports.

## Essential API

| Entry point | Purpose |
|---|---|
| `client.start` / `client.stop` | Negotiate the protocol (discover or handshake) and shut down |
| `client.tools` / `client.resources` / `client.prompts` | Indexed lists exposed by the server (title/icons preserved) |
| `client.call_tool(name, args)` | Invoke a tool; also `read_resource(uri)` and `get_prompt(name, args)` |
| `client.on_request(method)` / `on_elicitation` / `on_sampling` | Answer server-initiated requests (MRTR) |
| `client.listen(notifications)` | Open a `subscriptions/listen` notification stream |
| `server.notify_*_list_changed` | Emit change notifications to clients |
| `Ask::MCP::Adapters::AskTool.wrap(tools_hash)` | Adapter from MCP tools to `Ask::Tool` instances for ask-agent |
| `Ask::MCP::Adapters::ToolServer` | Adapter from duck-typed tools to MCP server tools |
| `Ask::MCP::Auth::Token.new(token)` | Token-based auth (`apply(headers)`) |
| `Ask::MCP::Auth::OAuth.new(client_id:, ...)` | OAuth for MCP; `discover!` (OIDC), `authenticate!`, `validate_iss!`, `apply(headers)` |
| `Ask::MCP::Auth::ClientIdMetadataDocument` | Build/validate Client ID Metadata Documents (2026-07-28 client registration) |
| `Ask::MCP::TraceContext` | OpenTelemetry `traceparent`/`tracestate`/`baggage` extraction for `_meta` |
| `Ask::MCP::XMcpHeader` | Validation of `x-mcp-header` tool annotations |

OAuth endpoints can be discovered instead of configured:

```ruby
oauth = Ask::MCP::Auth::OAuth.new(client_id: "my-client", issuer: "https://auth.example.com")
oauth.discover!          # fetches /.well-known/openid-configuration
oauth.authenticate!      # client-credentials or authorization-code flow
client = Ask::MCP::Client.new(transport, auth: oauth)
```

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
ask-auth, and [docs/SPEC_COMPLIANCE.md](docs/SPEC_COMPLIANCE.md) for the
protocol compliance status. API reference: https://ask-rb.github.io/ask-docs/reference/api.

## Development

bundle install
bundle exec rake test   # full suite + self-contained conformance (both protocol eras)

## License

MIT
