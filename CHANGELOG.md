# Changelog

## [0.1.0] - 2026-06-10

### Added
- Core MCP client with full JSON-RPC 2.0 message layer
- stdio transport for local process MCP servers
- SSE transport for remote Server-Sent Events MCP servers
- Streamable HTTP transport for remote HTTP MCP servers
- Tool, Resource, and Prompt data models with `from_h`/`to_h` serialization
- Client lifecycle: initialize, capabilities discovery, session management
- Tool calling, resource reading, and prompt retrieval
- Token-based authentication (Bearer/Basic)
- OAuth 2.1 authentication (client credentials + authorization code flows)
- Ask::Tool adapter for integration with ask-agent
- Thread-safe request/response matching with configurable timeouts
- Server-side notifications handling (tools/resources/prompts list changed)
- Comprehensive test suite with mock MCP server
- Factory methods: `from_stdio`, `from_sse`, `from_http`, `connect`
- Ability to cache or bypass caching for tools/resources/prompts
