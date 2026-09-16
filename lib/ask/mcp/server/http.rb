# frozen_string_literal: true

require "base64"
require "json"

module Ask
  module MCP
    class Server
      # MCP server over the stateless Streamable HTTP transport (2026-07-28).
      #
      # A Rack application. Every JSON-RPC message is one HTTP POST to the
      # endpoint and the server answers with a single application/json object.
      # The 2026-07-28 revision removed protocol-level sessions, the GET
      # stream endpoint and SSE resumability, so nothing here is stateful —
      # each request is dispatched by a fresh Core.
      #
      #   mount Ask::MCP::Server.rack_app(name: "anychat", tools: [...]) => "/mcp"
      #
      # Multi-tenant servers resolve tools per request. `authenticate`
      # receives the Rack env on every POST and returns whatever the host uses
      # to identify the caller; a nil return rejects the request with 401.
      # `tools` then receives that value:
      #
      #   HTTP.new(
      #     name: "anychat",
      #     authenticate: ->(env) { User.find_by_token(bearer_token(env)) },
      #     tools: ->(user) { user ? Tools.for(user) : [] }
      #   )
      #
      # Two spec obligations are deliberately left to the host or to a later
      # revision, and are called out here so nobody assumes otherwise:
      #
      # * Requests that carry `Mcp-Param-{Name}` headers are checked for legal
      #   field values, but not matched against the call arguments. Matching
      #   needs the calling tool's `x-mcp-header` annotations; no tool in this
      #   ecosystem declares them yet, so the condition cannot arise.
      # * Notifications raised while handling a request are dropped rather than
      #   streamed ahead of the response. This transport answers with
      #   application/json rather than text/event-stream, and the 2026-07-28
      #   channel for server-initiated changes is the opt-in
      #   subscriptions/listen stream, which is not implemented.
      class HTTP
        ERROR_CODES = Native::Messages::ErrorCodes

        NAME_BEARING_METHODS = %w[tools/call resources/read prompts/get].freeze
        JSON_CONTENT_TYPE = "application/json"
        MAX_BODY_BYTES = 1_048_576
        # Values that are not plain visible ASCII travel base64-encoded inside
        # this sentinel form (2026-07-28, SEP-2243). The markers are
        # case-sensitive.
        BASE64_SENTINEL = "=?base64?"
        BASE64_SENTINEL_END = "?="
        PARAM_HEADER_PREFIX = "HTTP_MCP_PARAM_"

        # @param allowed_origins [Array<String>, :any, nil] origins permitted to
        #   call this endpoint. nil — the default — trusts no browser origin,
        #   which still admits server-to-server clients because they send no
        #   Origin header at all.
        def initialize(name:, version: nil, tools: [], capabilities: { tools: {} },
                       resources: {}, prompts: {}, resource_templates: {},
                       debug: false, tool_timeout: nil, cache_ttl_ms: 60_000,
                       cache_scope: "private", authenticate: nil, context: nil,
                       allowed_origins: nil)
          @name = name
          @tools = tools
          @authenticate = authenticate
          @context = context
          @debug = debug
          @allowed_origins = allowed_origins
          @core_options = {
            name: name,
            version: version,
            capabilities: capabilities,
            resources: resources,
            prompts: prompts,
            resource_templates: resource_templates,
            debug: debug,
            tool_timeout: tool_timeout,
            cache_ttl_ms: cache_ttl_ms,
            cache_scope: cache_scope
          }
        end

        # Rack interface.
        def call(env)
          return forbidden unless origin_allowed?(env)
          return method_not_allowed(env) unless post?(env)

          if @authenticate
            context = @authenticate.call(env)
            return unauthorized unless context

            return dispatch(env, context)
          end

          dispatch(env, context_for(env))
        end

        private

        def dispatch(env, context)
          raw = read_body(env)
          return error_response(400, ERROR_CODES::PARSE_ERROR, "Empty request body") if raw.strip.empty?

          message = JSON.parse(raw, symbolize_names: true)
          unless message.is_a?(Hash)
            return error_response(400, ERROR_CODES::INVALID_REQUEST,
                                  "Expected a single JSON-RPC object (batching is not part of this revision)")
          end

          # A revision this server cannot speak is a transport-level failure
          # with its own error and status, so it is settled before validation.
          declared_version = env["HTTP_MCP_PROTOCOL_VERSION"].to_s
          if !declared_version.empty? && !Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS.include?(declared_version)
            return unsupported_version_response(declared_version, message[:id])
          end

          # The header requirements are specified for requests; a notification
          # is not one, and this revision defines no client-to-server
          # notifications over this transport, so notifications are accepted
          # without them.
          if message.key?(:id)
            violation = transport_violation(env, message)
            return error_response(400, ERROR_CODES::HEADER_MISMATCH, violation, id: message[:id]) if violation
          end

          core = build_core(context)
          core.handle_message(message)
          render(core.outbox)
        rescue JSON::ParserError => e
          error_response(400, ERROR_CODES::PARSE_ERROR, "Parse error: #{e.message}")
        end

        # Servers MUST validate the Origin header and refuse an Origin they do
        # not trust (2026-07-28): without this, a remote page can reach a
        # local MCP endpoint through DNS rebinding.
        def origin_allowed?(env)
          origin = env["HTTP_ORIGIN"].to_s
          return true if origin.empty?
          return false if @allowed_origins.nil?

          @allowed_origins == :any || Array(@allowed_origins).include?(origin)
        end

        def transport_violation(env, message)
          protocol_violation(env, message) ||
            method_violation(env, message) ||
            name_violation(env, message) ||
            param_value_violation(env)
        end

        # MCP-Protocol-Version is required on every POST and must agree with
        # the version the body declares in `_meta`: the body is authoritative,
        # the header exists so intermediaries can route without parsing it.
        # A request with no `_meta` version is a client expecting the removed
        # `initialize` handshake, which this stateless endpoint cannot honour.
        def protocol_violation(env, message)
          declared = env["HTTP_MCP_PROTOCOL_VERSION"].to_s
          return "Missing required MCP-Protocol-Version header" if declared.empty?

          body_version = Core.declared_protocol_version(message[:params] || {})
          if body_version.nil?
            return "MCP-Protocol-Version #{declared.inspect} has no matching " \
                   "#{Native::Messages::Meta::PROTOCOL_VERSION_KEY} in params._meta"
          end
          return nil if declared == body_version

          "MCP-Protocol-Version #{declared.inspect} does not match body value #{body_version.inspect}"
        end

        # Mcp-Method is required for all requests (2026-07-28, SEP-2243).
        def method_violation(env, message)
          method = message[:method].to_s
          declared = env["HTTP_MCP_METHOD"].to_s
          return "Missing required Mcp-Method header" if declared.empty?
          return nil if declared == method

          "Mcp-Method header #{declared.inspect} does not match method #{method.inspect}"
        end

        # Mcp-Name is required for the methods whose body carries a name.
        def name_violation(env, message)
          method = message[:method].to_s
          return nil unless NAME_BEARING_METHODS.include?(method)

          params = message[:params] || {}
          expected = (params[:name] || params[:uri]).to_s
          # A call missing its name is reported by the tool layer, with the
          # error shape that layer already owns.
          return nil if expected.empty?

          declared = decode_header_value(env["HTTP_MCP_NAME"])
          return "Missing required Mcp-Name header for #{method}" if declared.nil? || declared.empty?
          return nil if declared == expected

          "Mcp-Name header #{declared.inspect} does not match name #{expected.inspect}"
        end

        # Mirrored tool-parameter headers must carry legal field values, in
        # base64 sentinel form when they cannot (2026-07-28, SEP-2243).
        def param_value_violation(env)
          env.each do |key, value|
            next unless key.start_with?(PARAM_HEADER_PREFIX)
            next if header_value_legal?(value)

            return "#{header_name_for(key)} contains characters that require base64 encoding"
          end
          nil
        end

        def header_value_legal?(value)
          return base64_encoded?(value) if value.start_with?(BASE64_SENTINEL)

          value.each_char.all? do |char|
            char.ord == 0x09 || char.ord.between?(0x20, 0x7e)
          end
        end

        def base64_encoded?(value)
          return false unless value.end_with?(BASE64_SENTINEL_END)

          Base64.strict_decode64(sentinel_payload(value))
          true
        rescue ArgumentError
          false
        end

        # Header values that are not plain visible ASCII travel base64-encoded
        # in the =?base64?...?= sentinel form; servers MUST decode before
        # comparing them with the body. Base64 carries bytes and knows nothing
        # of encodings, and the spec defines the payload as the UTF-8
        # representation, so the decoded string is tagged as such — otherwise
        # it compares unequal to the same text from the body.
        def decode_header_value(value)
          return nil if value.nil?
          return value unless value.start_with?(BASE64_SENTINEL)

          Base64.strict_decode64(sentinel_payload(value)).force_encoding(Encoding::UTF_8)
        rescue ArgumentError
          value
        end

        def sentinel_payload(value)
          value[BASE64_SENTINEL.length..-(BASE64_SENTINEL_END.length + 1)]
        end

        # Rack folds header names into HTTP_MCP_PARAM_REGION; fold it back for
        # a message a human can act on.
        def header_name_for(key)
          key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
        end

        def build_core(context)
          Core.new(**@core_options, tools: resolve_tools(context))
        end

        def resolve_tools(context)
          return @tools unless @tools.respond_to?(:call)

          @tools.call(context) || []
        end

        def context_for(env)
          @context ? @context.call(env) : env
        end

        def render(outbox)
          response = outbox.reverse.find { |message| message.key?(:id) }
          dropped = outbox.count { |message| !message.key?(:id) }
          debug_log "Dropped #{dropped} notification(s): no channel for them on this transport" if dropped.positive?

          # A message with no id is a notification: accepted, nothing to say.
          return [202, json_headers, []] if response.nil?

          [status_for(response), json_headers, [JSON.generate(response)]]
        end

        # An RPC the server does not implement is a transport-level 404 with a
        # JSON-RPC -32601 body (2026-07-28); every other outcome is 200, with
        # failures inside the JSON-RPC envelope where they belong.
        def status_for(response)
          response.dig(:error, :code) == ERROR_CODES::METHOD_NOT_FOUND ? 404 : 200
        end

        def read_body(env)
          input = env["rack.input"]
          return "" unless input

          input.read(MAX_BODY_BYTES).to_s
        end

        def post?(env)
          env["REQUEST_METHOD"] == "POST"
        end

        def json_headers
          { "Content-Type" => JSON_CONTENT_TYPE }
        end

        def method_not_allowed(env)
          rpc_error(405, ERROR_CODES::METHOD_NOT_FOUND,
                    "Method not allowed: #{env['REQUEST_METHOD']} (this endpoint accepts POST)")
            .tap { |triple| triple[1] = triple[1].merge("Allow" => "POST") }
        end

        def unsupported_version_response(version, id)
          rpc_error(400, ERROR_CODES::UNSUPPORTED_PROTOCOL_VERSION,
                    "Unsupported protocol version: #{version}",
                    id: id, data: { supported: Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS })
        end

        def forbidden
          rpc_error(403, ERROR_CODES::INVALID_REQUEST, "Origin not allowed")
        end

        def unauthorized
          rpc_error(401, ERROR_CODES::AUTH_ERROR, "Unauthorized")
            .tap { |triple| triple[1] = triple[1].merge("WWW-Authenticate" => "Bearer") }
        end

        def error_response(status, code, message, id: nil)
          rpc_error(status, code, message, id: id)
        end

        # A rejection that the server could tie to a request echoes that
        # request's id, so a JSON-RPC client can correlate the failure with
        # what it sent. Failures raised before the body is understood — and the
        # 403 for an untrusted Origin — carry no id, which the spec allows.
        def rpc_error(status, code, message, id: nil, data: nil)
          error = { code: code, message: message }
          error[:data] = data if data
          body = { jsonrpc: "2.0", id: id, error: error }
          [status, json_headers, [JSON.generate(body)]]
        end

        def debug_log(message)
          return unless @debug

          warn "[ask-mcp] [#{@name}] #{message}"
        end
      end
    end
  end
end
