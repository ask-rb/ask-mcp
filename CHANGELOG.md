## [0.3.0] - 2026-06-26

### Changed
- Renamed `Adapters::AskToolServer` → `Adapters::ToolServer` — the adapter is
  now duck-typed and works with any Ruby object, not just Ask::Tool instances.
- README fully rewritten: leads with a general-purpose duck-typed server example
  instead of ask-tools-specific code. ask-rb integration is now a sub-section.
- Gemspec description updated to reflect general-purpose positioning.

## [0.2.0] - 2026-06-26

### Added
- Server Runtime: `Ask::MCP::Server::Stdio` — run as an MCP server over stdio
  with full initialize handshake, tool discovery, and tool call dispatch.
- `Adapters::AskToolServer` — converts tools to MCP definitions and dispatches calls.
- `Ask::MCP::Server.start_stdio` entry point for easy one-line server setup.

### Changed
- 56 new tests across adapter, server stdio, integration, and start_stdio (170 total).

## [0.1.1] - 2026-06-25

### Changed
- Major test expansion: Transport tests, MessagesParser, OAuth, Client, Server, Tool, Messages, integration. Rubocop, overcommit, CI matrix, SimpleCov.

## [0.1.0] - 2026-06-10

### Added
- Core MCP client with full JSON-RPC 2.0 message layer
- stdio, SSE, and Streamable HTTP transports
- Tool, Resource, and Prompt data models
- Client lifecycle, tool calling, resource reading, prompt retrieval
- Token-based and OAuth 2.1 authentication
- Ask::Tool adapter for ask-agent integration
- Thread-safe request/response matching with configurable timeouts
- Server-side notifications handling
- Factory methods: `from_stdio`, `from_sse`, `from_http`, `connect`
