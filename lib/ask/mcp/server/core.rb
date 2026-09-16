# frozen_string_literal: true

require "json"
require "timeout"

module Ask
  module MCP
    class Server
      # Transport-agnostic MCP request processing.
      #
      # A Core owns one server's tools, resources and prompts and turns a
      # single parsed JSON-RPC message into the messages the server wants to
      # send back. Transports differ only in how those messages reach the
      # client: Stdio writes each one to $stdout as it is produced, the HTTP
      # transport collects them in #outbox and renders a response.
      #
      # Negotiated protocol state (`@protocol_version`) lives on the instance,
      # so a stateless transport builds a Core per request rather than sharing
      # one across callers.
      class Core
        MAX_RESULT_CACHE = 100

        attr_reader :name, :tools, :capabilities, :resources, :prompts,
                    :resource_templates, :outbox

        # The protocol version a request declares in params `_meta`, or nil for
        # a legacy request that expects an `initialize` handshake. Handles both
        # symbol and string key forms (the JSON parser symbolizes all keys).
        def self.declared_protocol_version(params)
          meta = params[:meta] || params[:_meta] || {}
          key = Native::Messages::Meta::PROTOCOL_VERSION_KEY
          meta[key] || meta[key.to_sym] || meta[key.to_s]
        end

        def initialize(name:, version: nil, tools: [], capabilities: { tools: {} },
                       resources: {}, prompts: {}, resource_templates: {},
                       debug: false, tool_timeout: nil, cache_ttl_ms: 60_000,
                       cache_scope: "private")
          @name = name
          @server_version = version || Ask::MCP::VERSION
          @tools = tools || []
          @capabilities = capabilities
          @resources = resources
          @prompts = prompts
          @resource_templates = resource_templates
          @debug = debug
          @tool_timeout = tool_timeout
          @cache_ttl_ms = cache_ttl_ms
          @cache_scope = cache_scope

          @adapter = Adapters::ToolServer.new(@tools)
          @outbox = []
          @initialized = false
          @result_cache = {}
          # Negotiated protocol version. nil until the client tells us which
          # revision it speaks (legacy `initialize` or stateless `_meta`).
          @protocol_version = nil
        end

        # Methods held behind the legacy gate. A stateless (2026-07-28) request
        # opens them by declaring its version; a legacy client opens them with
        # `initialize`.
        GATED_METHODS = %w[
          tools/list tools/call
          resources/list resources/read resources/templates/list
          prompts/list prompts/get
        ].freeze

        # Process one JSON-RPC message (symbolized keys). Every message the
        # server produces is handed to #deliver, in order.
        def handle_message(msg)
          method = msg[:method]
          id = msg[:id]
          params = msg[:params] || {}
          has_id = msg.key?(:id)

          # A stateless (2026-07-28) request carries its protocol version in
          # `_meta` instead of an `initialize` handshake; a version this server
          # does not speak is answered here and the message stops.
          version = meta_protocol_version(params)
          if version && !supported_version?(version)
            return send_error(id, Native::Messages::ErrorCodes::UNSUPPORTED_PROTOCOL_VERSION,
                              "Unsupported protocol version: #{version}")
          end

          adopt_version(version)
          return send_error(id, -32_000, "Server not initialized") if gated?(method) && !@initialized

          case method
          when "initialize"
            handle_initialize(id, params)
          when "server/discover"
            handle_discover(id)
          when "notifications/initialized"
            @initialized = true
            debug_log "Client initialized"
          when "tools/list"
            handle_tools_list(id)
          when "tools/call"
            handle_tool_call(id, params)
          when "resources/list"
            handle_resources_list(id)
          when "resources/read"
            handle_resource_read(id, params)
          when "resources/templates/list"
            handle_resources_templates_list(id)
          when "prompts/list"
            handle_prompts_list(id)
          when "prompts/get"
            handle_prompt_get(id, params)
          when "ping"
            # ping was removed in 2026-07-28; legacy clients still use it.
            if stateless_mode?
              send_error(id, Native::Messages::ErrorCodes::METHOD_NOT_FOUND, "Method not found: ping") if has_id
            elsif has_id
              send_result(id, {})
            end
          else
            debug_log "Unknown method: #{method}"
            send_error(id, Native::Messages::ErrorCodes::METHOD_NOT_FOUND, "Method not found: #{method}") if has_id
          end
        end

        private

        # Hand an outbound message to the transport. The default collects into
        # #outbox; Stdio overrides this to write to $stdout as messages appear.
        def deliver(message)
          @outbox << message
        end

        # Adopt the protocol version a stateless (2026-07-28) request declares
        # in `_meta`; that declaration is what unlocks the handlers without the
        # legacy gate. A legacy request declares nothing, so the gate stands.
        def adopt_version(version)
          return if version.nil?

          @protocol_version = version
          @initialized = true
          debug_log "Stateless request (protocol #{version})"
        end

        # server/discover (2026-07-28): advertise supported protocol versions,
        # capabilities, and identity. Clients call it before anything else to
        # select a version (or as a backward-compat probe on stdio).
        def handle_discover(id)
          send_result(id, {
                        protocolVersions: Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS,
                        capabilities: @capabilities,
                        serverInfo: { name: @name, version: @server_version }
                      })
          debug_log "server/discover answered"
        end

        def handle_initialize(id, params)
          @initialized = true
          @protocol_version = params[:protocolVersion] || Ask::MCP::PROTOCOL_VERSION
          client_version = params[:protocolVersion] || Ask::MCP::PROTOCOL_VERSION
          debug_log "Handling initialize (id=#{id.inspect}, version=#{client_version})"
          send_result(id, {
                        protocolVersion: client_version,
                        capabilities: @capabilities,
                        serverInfo: {
                          name: @name,
                          version: @server_version
                        }
                      })
          debug_log "Initialize complete"
        end

        def handle_tools_list(id)
          defs = @adapter.definitions
          debug_log "tools/list returning #{defs.length} tool definitions"
          send_result(id, cacheable({ tools: defs }))
        end

        def handle_resources_list(id)
          defs = @resources.values.map { |r| resource_to_h(r) }
          debug_log "resources/list returning #{defs.length} resources"
          send_result(id, cacheable({ resources: defs }))
        end

        def handle_resources_templates_list(id)
          defs = @resource_templates.values.map { |t| template_to_h(t) }
          debug_log "resources/templates/list returning #{defs.length} templates"
          send_result(id, cacheable({ resourceTemplates: defs }))
        end

        def handle_resource_read(id, params)
          uri = params[:uri].to_s
          resource = @resources[uri]
          if resource.nil?
            code = stateless_mode? ? Native::Messages::ErrorCodes::INVALID_PARAMS : Native::Messages::ErrorCodes::RESOURCE_NOT_FOUND
            return send_error(id, code, "Resource not found: #{uri}")
          end

          contents = if resource.respond_to?(:content)
                       resource.content
                     elsif resource.respond_to?(:read)
                       resource.read
                     else
                       [{ uri: uri, text: "" }]
                     end
          send_result(id, cacheable({ contents: contents }))
        end

        def handle_prompts_list(id)
          defs = @prompts.values.map { |p| prompt_to_h(p) }
          debug_log "prompts/list returning #{defs.length} prompts"
          send_result(id, cacheable({ prompts: defs }))
        end

        def handle_prompt_get(id, params)
          name = params[:name].to_s
          prompt = @prompts[name]
          if prompt.nil?
            return send_error(id, Native::Messages::ErrorCodes::PROMPT_NOT_FOUND, "Prompt not found: #{name}")
          end

          messages = prompt.respond_to?(:messages) ? prompt.messages : []
          send_result(id, { messages: messages })
        end

        def handle_tool_call(id, params)
          cache_key = id.to_s

          # Return cached result for retried requests (same ID, already processed)
          if @result_cache.key?(cache_key)
            debug_log "Returning cached result for id=#{id}"
            return send_result(id, @result_cache[cache_key])
          end

          tool_name = params[:name].to_s
          arguments = params[:arguments] || {}

          debug_log "Handling tools/call: #{tool_name} (id=#{id.inspect})"

          result = if @tool_timeout
                     Timeout.timeout(@tool_timeout) { @adapter.call(tool_name, arguments) }
                   else
                     @adapter.call(tool_name, arguments)
                   end

          @result_cache[cache_key] = result
          trim_cache

          send_result(id, result)
        rescue Timeout::Error
          debug_log "Tool call timed out: #{tool_name}"
          send_result(id, {
                        content: [{ type: "text", text: "Tool call timed out: #{tool_name}" }],
                        isError: true
                      })
        end

        # Serialize a resource object for resources/list. Prefers to_h (the
        # Resource value object emits title/icons/description/mimeType);
        # otherwise builds the shape from duck-typed accessors.
        def resource_to_h(resource)
          return resource.to_h if resource.respond_to?(:to_h)

          h = { uri: resource.uri, name: resource.name }
          h[:title] = resource.title if resource.respond_to?(:title) && resource.title
          h[:description] = resource.description if resource.respond_to?(:description) && resource.description
          h[:mimeType] = resource.mime_type if resource.respond_to?(:mime_type) && resource.mime_type
          h[:icons] = resource.icons if resource.respond_to?(:icons) && resource.icons&.any?
          h
        end

        def template_to_h(template)
          return template.to_h if template.respond_to?(:to_h)

          h = { uriTemplate: template.uri_template, name: template.name }
          h[:title] = template.title if template.respond_to?(:title) && template.title
          h[:mimeType] = template.mime_type if template.respond_to?(:mime_type) && template.mime_type
          h[:icons] = template.icons if template.respond_to?(:icons) && template.icons&.any?
          h
        end

        def prompt_to_h(prompt)
          return prompt.to_h if prompt.respond_to?(:to_h)

          h = { name: prompt.name }
          h[:title] = prompt.title if prompt.respond_to?(:title) && prompt.title
          h[:description] = prompt.description if prompt.respond_to?(:description) && prompt.description
          h[:arguments] = prompt.arguments if prompt.respond_to?(:arguments) && prompt.arguments&.any?
          h[:icons] = prompt.icons if prompt.respond_to?(:icons) && prompt.icons&.any?
          h
        end

        def send_result(id, result)
          result = result.merge(stateless_result_fields) if stateless_mode?
          deliver({ jsonrpc: "2.0", id: id, result: result })
        end

        # 2026-07-28: every result carries `resultType`, and servers SHOULD
        # identify themselves in `_meta` so a client can attribute an answer
        # without a separate discovery round trip. Legacy peers tolerate both
        # fields, but we only emit them for stateless peers so the legacy wire
        # output is unchanged.
        def stateless_result_fields
          {
            resultType: "complete",
            _meta: { Native::Messages::Meta::SERVER_INFO_KEY => server_info }
          }
        end

        def server_info
          { name: @name, version: @server_version }
        end

        # Build a server→client notification (no id).
        def send_notification(method, params = {})
          msg = { jsonrpc: "2.0", method: method }
          msg[:params] = params unless params.empty?
          deliver(msg)
        end

        # 2026-07-28 CacheableResult: freshness hints (ttlMs) and scope
        # (public/private) on list/read results so clients and shared
        # intermediaries may cache them. Only emitted for stateless peers.
        def cacheable(result)
          return result unless stateless_mode?

          result.merge(ttlMs: @cache_ttl_ms, cacheScope: @cache_scope)
        end

        # True once a 2026-07-28 stateless peer has been detected.
        def stateless_mode?
          @protocol_version == Ask::MCP::LATEST_PROTOCOL_VERSION
        end

        def supported_version?(version)
          Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS.include?(version)
        end

        def gated?(method)
          GATED_METHODS.include?(method)
        end

        # Read the protocol version a stateless client advertises in params
        # `_meta`. Returns nil for legacy requests. Handles both symbol and
        # string key forms (the JSON parser symbolizes all keys).
        def meta_protocol_version(params)
          meta = params[:meta] || params[:_meta] || {}
          meta_value(meta, Native::Messages::Meta::PROTOCOL_VERSION_KEY)
        end

        def meta_value(meta, key)
          meta[key] || meta[key.to_sym] || meta[key.to_s]
        end

        def send_error(id, code, message)
          deliver({ jsonrpc: "2.0", id: id, error: { code: code, message: message } })
        end

        def debug_log(msg)
          return unless @debug

          ts = Time.now.strftime("%H:%M:%S.%L")
          warn "[#{ts}] [#{@name}] #{msg}"
        end

        def trim_cache
          return if @result_cache.size <= MAX_RESULT_CACHE

          @result_cache.shift(@result_cache.size - MAX_RESULT_CACHE)
        end
      end
    end
  end
end
