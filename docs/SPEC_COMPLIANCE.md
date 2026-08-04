# ask-mcp — MCP Specification Compliance

Status of `ask-mcp` against the Model Context Protocol specification.

**Advertised versions:** `Ask::MCP::PROTOCOL_VERSION` = `2025-06-18` (legacy
default), `Ask::MCP::LATEST_PROTOCOL_VERSION` = `2026-07-28` (stateless),
`Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS` = `[2025-06-18, 2025-11-25,
2026-07-28]`. Clients negotiate via `server/discover` (falling back to the
legacy `initialize` handshake); servers speak both eras on one connection.

## Strategy (applies to every item below)

1. **Single source of truth.** Protocol constants live on `Ask::MCP`; client
   and server reference them. This is what the `0.1.0` bug was about — never
   reintroduce per-class duplicates.
2. **Dual-mode, not rewrite.** `2026-07-28` removed the `initialize`
   handshake, but the spec *requires* backward compatibility with older peers
   (missing `resultType` → treat as `"complete"`; `server/discover` as a
   backward-compat probe on stdio; `UnsupportedProtocolVersionError`). The
   gem speaks the old and new protocols at once, negotiated per peer.
3. **Tests first, wire-level.** Where a change alters what goes over the
   wire, assert on the wire: `RecordingTransport` (unit, no subprocess) for
   the client, `MCPServerHarness` for the server.
4. **Don't build on deprecated features.** Roots, Sampling, Logging, the
   HTTP+SSE transport, and OAuth Dynamic Client Registration are deprecated
   as of `2026-07-28` — keep existing support working, don't add new surface.

---

## 1. Baseline: `2025-06-18` (done)

- [x] `initialize` / `notifications/initialized` handshake (client + server)
- [x] stdio transport
- [x] Streamable HTTP transport
- [x] HTTP+SSE transport (legacy, deprecated)
- [x] `tools/list`, `tools/call` (+ retry dedup, timeouts, graceful shutdown)
- [x] `resources/list`, `resources/read`, `resources/templates/list`
- [x] `prompts/list`, `prompts/get`
- [x] `ping` (legacy only — removed for 2026-07-28 peers)
- [x] OAuth resource-server authorization (`auth/oauth.rb`)
- [x] JSON-RPC 2.0 message types, parser, error codes (`native/messages.rb`)
- [x] Server serves tools, resources, prompts, and resource templates
  (duck-typed serialization; `Server.start_stdio` accepts `resources`,
  `prompts`, `resource_templates`)

## 2. `2025-11-25` gap (done)

- [x] **Icons + title display metadata (SEP-973)** — `title` (optional) and
  `icons` (array of `{src, mimeType, sizes}`) on tools, resources, prompts;
  parsed/emitted by the value objects, passed through by
  `Adapters::ToolServer`.
- [x] **Server serves resources & prompts** — `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, `prompts/get`
  handlers in `Server::Stdio`; `resources/read`/`prompts/get` pull contents
  from `content`/`read`/`messages` or return the spec error codes.
- [x] **OIDC discovery (1.0)** — `Auth::OAuth#discover!` fetches
  `/.well-known/openid-configuration` (derived from `issuer` per RFC 8414 or
  an explicit `discovery_url`) and populates `token_url`, `auth_url`,
  `issuer`; `token_url` is now optional at construction.
- [x] **Elicitation** — client handles `elicitation/create` via
  `on_elicitation` (schema/params passed through verbatim, so titled/untitled,
  single/multi-select enums and defaults are supported by construction).
- [x] **Sampling with tool calling (SEP-1577)** — client handles
  `sampling/createMessage` via `on_sampling`, passing `tools`/`toolChoice`
  through untouched.
- [x] **JSON Schema 2020-12 as default dialect** — `Validator` accepts
  schemas declaring the 2020-12 dialect (the json-schema gem lacks 2020-12,
  so the metaschema is stripped and validation retried; shared keywords
  including `const` are enforced).
- [x] **Tool-name guidance** — spec is SHOULD-level; ask-mcp does not reject
  tool names.
- [~] **Experimental Tasks** — explicitly not implemented: deprecated in
  2026-07-28 in favor of the `io.modelcontextprotocol/tasks` extension.

## 3. `2026-07-28` (stateless revision) — done, dual-mode

### 3.1 Stateless core

- [x] **`server/discover`** — server advertises `protocolVersions`,
  `capabilities`, `serverInfo`; client probes it first and falls back to the
  legacy handshake when the method is unknown (`UnsupportedProtocolVersion`
  semantics via negotiated version lists).
- [x] **Remove `initialize` handshake in stateless mode** — every request
  carries `_meta` (`io.modelcontextprotocol/protocolVersion`,
  `clientCapabilities`, `clientInfo`); server identifies itself in results
  via `serverInfo` (in discover) and `resultType`. Legacy handshake kept for
  older peers; a server that supports ≤ 2025-11-25 is detected and the client
  still handshakes with the negotiated version.
- [x] **`resultType` on all results** — server emits `"complete"` for
  stateless peers (and `"input_required"` on MRTR); clients treat missing as
  `"complete"` per spec.
- [x] **MRTR (Multi Round-Trip Requests, SEP-2322)** — client resolves
  `inputRequests` (elicitation/sampling/roots) through the registered
  handlers, retries with `inputResponses`, echoes `requestState` verbatim,
  uses a fresh JSON-RPC id per retry, and caps round trips.
- [x] **Remove `ping`, `logging/setLevel`, `notifications/roots/list_changed`**
  — `ping` returns Method-not-found for stateless peers (`logging/setLevel`
  and roots notifications were never implemented; nothing to remove).
- [x] **Error-code allocation policy** — `-32020..-32099` reserved:
  `HeaderMismatch` `-32020`, `MissingRequiredClientCapability` `-32021`,
  `UnsupportedProtocolVersion` `-32022`; resource-not-found renumbered to
  `-32602` for stateless peers.

### 3.2 Transports

- [x] **Streamable HTTP: stateless shape** — no `Mcp-Session-Id`, no GET
  stream endpoint, no `Last-Event-ID`; one POST per message; per-response
  Content-Type decides single JSON vs SSE stream; SSE comment (keep-alive)
  lines ignored.
- [x] **Required request headers** — `MCP-Protocol-Version` (matching body
  `_meta`), `Mcp-Method`, `Mcp-Name` (`params.name`/`params.uri` for
  `tools/call`, `resources/read`, `prompts/get`), with Base64 sentinel value
  encoding for non-ASCII/unsafe values.
- [x] **x-mcp-header param mirroring (SEP-2243)** — client mirrors annotated
  tool parameters into `Mcp-Param-{Name}` headers with value encoding, and
  validates the annotations (`Ask::MCP::XMcpHeader`): empty names, invalid
  field-name characters, non-primitive types, case-insensitive duplicates,
  and annotations not statically reachable via a `properties`-only chain
  (items/composition/conditionals/$ref/$defs) all make a tool definition
  invalid, and Streamable HTTP clients exclude such tools from `tools/list`
  with a warning. Integer values outside the JavaScript safe range are
  omitted from headers at call time.
- [x] **`subscriptions/listen`** — transport opens the long-lived POST
  response stream; `Client#listen(notifications)` convenience; delivered
  notifications flow into the client's cache-invalidation handling.
  Server-side emission: `Server::Stdio#notify_tools_list_changed` /
  `notify_resources_list_changed` / `notify_prompts_list_changed` write the
  notifications (deterministically ordered before the triggering response);
  clients invalidate their caches on receipt (verified end-to-end).
- [x] **HTTP+SSE transport deprecated (SEP-2596)** — marked in code/docs;
  still functional for legacy servers.

### 3.3 Results, caching, errors

- [x] **`CacheableResult`** — `ttlMs` + `cacheScope` (`"private"` default,
  configurable) emitted on `tools/list`, `resources/list`,
  `resources/templates/list`, `resources/read`, `prompts/list` for stateless
  peers.
- [x] **Deterministic tool ordering** — `tools/list` order is stable (locked
  by test) for client caching and prompt-cache hit rates.
- [x] **`extensions` capability field** — capabilities are caller-provided
  pass-through, so extension capabilities are supported by construction.

### 3.4 Authorization

- [x] **Issuer tracking** — `discover!` records the discovered `issuer`.
- [x] **`iss` validation (RFC 9207)** — `Auth::OAuth#validate_iss!` rejects
  an `iss` that does not match the recorded issuer.
- [x] **Client ID Metadata Documents (SEP-991)** —
  `Auth::ClientIdMetadataDocument` builds and validates the self-hosted JSON
  document (required `client_id`/`client_name`/`redirect_uris`, https URL
  client_id with a path, `client_id` matching the document URL,
  `application_type` `native`/`web` with `native` default for CLI clients).
  URL-based client IDs are portable across authorization servers, so no
  re-registration is needed when the server changes.
- [x] **Credential binding by issuer** — satisfied by construction: each
  `OAuth` instance holds credentials for the single authorization server it
  is configured/discovered against (no shared credential store exists).
- [~] **`application_type` in Dynamic Client Registration** — ask-mcp has no
  DCR implementation (it is deprecated in 2026-07-28); `application_type` is
  supported via the Client ID Metadata Document builder.

### 3.5 Deprecations (keep working, don't extend)

- [x] Roots, Sampling, Logging marked deprecated (no new build-out; the
  client still exposes `on_sampling`/elicitation handlers for MRTR).
- [x] **OTel trace context conventions (SEP-414)** — `Ask::MCP::TraceContext`
  extracts `traceparent`/`tracestate`/`baggage` from HTTP headers (incl.
  Rack's `HTTP_*` convention) and from `_meta`; clients propagate configured
  `_meta` fields (e.g. `meta: TraceContext.from_headers(rack_env)`).

## 4. Conformance / verification

- Unit (no subprocess): `bundle exec ruby -Itest test/client_test.rb`
- Server (harness + subprocess): `bundle exec ruby -Itest test/server/stdio_test.rb`
- Transports: `bundle exec ruby -Itest test/transport/`
- Full suite: `bundle exec rake test`
- Status: 299 runs, 686 assertions, 0 failures (green across repeated runs).

Conformance: `test/conformance_test.rb` is the self-contained stand-in for the
official MCP test suite — it runs the full lifecycle against the real server
in both the `2025-06-18` handshake era and the `2026-07-28` stateless era, plus
a stateless client end-to-end. Run the official MCP fixtures here too once the
2026-07-28 fixtures are published.
