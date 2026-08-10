## [0.4.4] - 2026-08-10

### Fixed

- **Hash tool results are JSON-serialized instead of emitted raw** —
  `ToolServer#wrap_result`/`success_result` used `result[:summary]` as the
  content `text` whenever a Hash result had a `summary` key. When `summary`
  was itself a Hash (e.g. `schema_graph`'s summary), the server emitted a
  non-string content item that spec-compliant MCP clients reject. String
  `summary` values are still honored as a shorthand; any other Hash result is
  `JSON.generate`d so `text` is always a String.

## [0.4.3] - 2026-08-04

### Added

- **serverInfo version passthrough** — `Ask::MCP::Server.start_stdio` and
  `Ask::MCP::Server::Stdio.new` accept a `version:` option reported in the
  `serverInfo` of both the legacy `initialize` handshake and
  `server/discover`. Defaults to the ask-mcp version when omitted, so
  wrapper servers (ask-web-search-mcp, ask-web-fetch-mcp) can advertise
  their own gem version instead of ask-mcp's.

## [0.4.2] - 2026-08-04

### Added

- **2026-07-28 stateless protocol core (dual-mode)** — new
  `Ask::MCP::LATEST_PROTOCOL_VERSION` (`"2026-07-28"`) and
  `SUPPORTED_PROTOCOL_VERSIONS` constants. The client probes
  `server/discover` and, for a 2026-07-28 peer, skips the `initialize`
  handshake and sends every request with `_meta`
  (`io.modelcontextprotocol/protocolVersion`, `clientCapabilities`,
  `clientInfo`). The server answers `server/discover`, detects stateless
  requests from `_meta`, and keeps the legacy handshake for older peers. A
  server that supports only ≤ 2025-11-25 is detected and still handshakes
  with the negotiated version.
- **`resultType` on server results** — `"complete"` for stateless peers
  (`"input_required"` via MRTR).
- **MRTR (Multi Round-Trip Requests)** — the client resolves
  `inputRequests` through the `on_elicitation`/`on_sampling`/`on_request`
  handlers, retries the original request with `inputResponses`, echoes
  `requestState` verbatim, uses a fresh JSON-RPC id per retry, and caps round
  trips (`MAX_MRTR_ROUND_TRIPS`).
- **Server-initiated request framework** — `Client#on_request` plus
  `on_elicitation` and `on_sampling` conveniences; the client declares
  support via `client_capabilities`.
- **Streamable HTTP rework (2026-07-28 shape)** — one POST per message with
  `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name` headers (Base64 sentinel
  value encoding); per-response Content-Type decides single JSON vs SSE
  stream; SSE keep-alive comments ignored; `subscriptions/listen` long-lived
  streams via `Transport::StreamableHTTP#listen` / `Client#listen`; x-mcp-
  header tool parameters mirrored into `Mcp-Param-{Name}` headers. Sessions,
  the GET endpoint, and `Last-Event-ID` were removed upstream and are not
  implemented. `base64` added as a runtime dependency (Ruby 3.4+).
- **x-mcp-header validation (SEP-2243)** — `Ask::MCP::XMcpHeader` validates
  annotations (empty names, invalid characters, non-primitive types,
  case-insensitive duplicates, non-`properties`-reachable placement);
  Streamable HTTP clients exclude invalid tool definitions from `tools/list`
  with a warning; out-of-range integers are omitted from headers.
- **OTel trace context (SEP-414)** — `Ask::MCP::TraceContext` extracts
  `traceparent`/`tracestate`/`baggage` from headers (incl. Rack `HTTP_*`) and
  `_meta`; clients propagate configured `_meta` fields via `meta:` option.
- **Server list_changed notifications** — `Server::Stdio#notify_tools_
  list_changed`, `#notify_resources_list_changed`, `#notify_prompts_
  list_changed` emit the change notifications (deterministically ordered
  before the triggering response); the client invalidates its caches on
  receipt. Verified end-to-end with a dedicated notify test server.
- **Client ID Metadata Documents (SEP-991)** — `Auth::ClientIdMetadataDocument`
  builds and validates the self-hosted client metadata document (required
  fields, https URL client_id with path, URL/client_id match,
  `application_type` native/web) — the 2026-07-28 recommended replacement
  for the deprecated Dynamic Client Registration.
- **RFC 9207 `iss` validation** — `Auth::OAuth#validate_iss!` rejects an
  `iss` that does not match the recorded issuer.
- **`CacheableResult`** — `ttlMs` + `cacheScope` (configurable via
  `cache_ttl_ms`/`cache_scope`) emitted on list/read results for stateless
  peers; deterministic `tools/list` ordering locked by test.
- **`ping` removed for 2026-07-28 peers** (Method-not-found); legacy clients
  still get `{}`.
- **Error-code allocation policy** — `HEADER_MISMATCH` `-32020`,
  `MISSING_REQUIRED_CLIENT_CAPABILITY` `-32021`,
  `UNSUPPORTED_PROTOCOL_VERSION` `-32022`; resource-not-found renumbered to
  `-32602` for stateless peers.
- **OIDC Discovery 1.0 (2025-11-25)** — `Auth::OAuth#discover!` resolves
  endpoints from `/.well-known/openid-configuration` (issuer-derived or
  explicit URL); `token_url` is now optional at construction.
- **JSON Schema 2020-12 dialect** — `Validator` accepts schemas declaring the
  2020-12 metaschema (strips it and retries on the json-schema gem, which
  lacks 2020-12); `const` and other shared keywords enforced.
- **2025-11-25 display metadata (SEP-973)** — `Tool`, `Resource`, and
  `Prompt` now parse (`from_h`) and emit (`to_h`) the optional `title` and
  `icons` (array of `{src, mimeType, sizes}`) fields, and
  `Adapters::ToolServer` passes them through in `tools/list` definitions
  when the tool object provides them. Clients connecting to 2025-11-25
  servers no longer drop these fields.
- **Server now serves resources & prompts** — `Server::Stdio` implements
  `resources/list`, `resources/read`, `resources/templates/list`,
  `prompts/list`, and `prompts/get` (previously only tools were served).
  Duck-typed resource/prompt/template objects are serialized from their
  accessors, and `Server.start_stdio` accepts `resources`, `prompts`, and
  `resource_templates` keyword args.
- `RecordingTransport` test helper (`test/support/recording_transport.rb`) —
  in-memory transport for asserting what `Client` puts on the wire without
  spawning a subprocess.
- `docs/SPEC_COMPLIANCE.md` — full compliance status across all three
  revisions (2025-06-18 / 2025-11-25 / 2026-07-28).

### Changed

- HTTP+SSE transport marked deprecated (2026-07-28 feature lifecycle);
  still functional for legacy servers. Prefer Streamable HTTP.
- `send` on transports now accepts an optional extra-headers argument
  (used for `Mcp-Param-*` mirroring; ignored by stdio/SSE).

### Fixed

- **Client advertised a bogus protocol version** — `Ask::MCP::Client` sent
  `protocolVersion: "0.1.0"` in `initialize` while `Server::Stdio` pinned
  `2025-06-18`. The advertised MCP revision is now a single source of truth,
  `Ask::MCP::PROTOCOL_VERSION` (`"2025-06-18"`), referenced by both client and
  server; the old per-class constants remain as deprecated aliases.
- **Flaky subprocess timing tests** — `test_transport_send_and_receive` and
  `test_sigterm_triggers_shutdown` failed intermittently under CI load.
  Replaced fixed `sleep`s with a shared `wait_until` poll-until-deadline
  helper (`test/test_helper.rb`); `test_spawn_and_communicate` now does a
  real round-trip via `cat` instead of an assertion that could never fail.

## [0.4.1] - 2026-07-31

### Changed

- **`ToolServer` result wrapping** — plain `String` results are always treated
  as success; result-like objects (`Ask::Result`, OpenStruct, etc.) use
  `ok?`/`ok` and `output`/`error_message`; any other value is treated as
  success with `to_s` used for the response.

### Fixed

- **Stdio server protocol version** — pins `PROTOCOL_VERSION` to
  `2025-06-18` and echoes it back in the `initialize` response.

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
