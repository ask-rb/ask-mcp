## [0.4.0] - 2026-06-26

### Added
- Request ID deduplication — retried `tools/call` with the same ID returns
  cached result instead of re-executing the tool.
- SIGTERM/SIGHUP graceful shutdown — closes stdin to unblock the read loop
  so the current tool call can finish before the process exits.
- Configurable `tool_timeout` option — prevents hung tool calls from
  blocking the server indefinitely.
- `ping` handler for MCP keepalive support.
- 10 new tests: request dedup (3), tool timeout (2), SIGTERM (1),
  multiline JSON safety (3), ping (1) — 180 total.

### Changed
- `Server::Stdio` now echoes back the client's requested protocol version
  instead of hardcoding a value.

## [0.3.0] - 2026-06-26

### Changed
- Renamed `Adapters::AskToolServer` → `Adapters::ToolServer` — duck-typed,
  works with any Ruby object, not just Ask::Tool instances.
- README rewritten to lead with general-purpose duck-typed server example.
- ask-rb integration is now a documented sub-section.

## [0.2.0] - 2026-06-26

### Added
- Server Runtime: `Ask::MCP::Server::Stdio` with full initialize handshake.
- `Server.start_stdio` entry point for one-line server setup.
- 56 new tests (170 total at time of release).

## [0.1.1] - 2026-06-25

### Changed
- Major test expansion across all modules.

## [0.1.0] - 2026-06-10

### Added
- Core MCP client with JSON-RPC 2.0 message layer.
- stdio, SSE, and Streamable HTTP transports.
- Tool, Resource, Prompt data models.
- OAuth 2.1 and token-based authentication.
- ask-agent integration via AskTool adapter.
