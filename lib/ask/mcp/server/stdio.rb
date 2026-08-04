# frozen_string_literal: true

require "json"
require "timeout"

module Ask
  module MCP
    class Server
      # MCP server over stdio transport.
      class Stdio
        MAX_RESULT_CACHE = 100
        # Deprecated: use Ask::MCP::PROTOCOL_VERSION (the canonical constant).
        PROTOCOL_VERSION = Ask::MCP::PROTOCOL_VERSION

        attr_reader :name, :tools, :capabilities, :resources, :prompts

        def initialize(name:, tools: [], capabilities: {}, resources: {}, prompts: {},
                       resource_templates: {}, debug: false, tool_timeout: nil,
                       cache_ttl_ms: 60_000, cache_scope: "private")
          @name = name
          @capabilities = capabilities
          @resources = resources
          @prompts = prompts
          @resource_templates = resource_templates
          @debug = debug
          @tool_timeout = tool_timeout
          @cache_ttl_ms = cache_ttl_ms
          @cache_scope = cache_scope

          @adapter = Adapters::ToolServer.new(tools || [])
          @initialized = false
          @running = false
          @shutdown_requested = false
          @result_cache = {}
          # Negotiated protocol version. nil until the client tells us which
          # revision it speaks (legacy `initialize` or stateless `_meta`).
          @protocol_version = nil
          @stateless = false
        end

        def start
          @running = true
          $stdout.sync = true

          # Graceful shutdown: on TERM/HUP, set flag and close stdin to
          # unblock the read loop so the current tool call can finish.
          trap("TERM") { graceful_shutdown }
          trap("HUP")  { graceful_shutdown }

          debug_log "Server starting: #{@name} (PID #{Process.pid})"
          debug_log "Tools: #{@adapter.definitions.map { |d| d[:name] }.join(', ')}"

          while @running && !@shutdown_requested && (line = $stdin.gets)
            line = line.strip
            next if line.empty?
            process_line(line)
          end

          debug_log "stdin closed — exiting"
        rescue Errno::EBADF, IOError
          # stdin closed externally (e.g. from trap handler)
        rescue SignalException
          # SIGTERM or SIGHUP during blocked read
        ensure
          @running = false
          @shutdown_requested = false
          trap("TERM", "DEFAULT")
          trap("HUP", "DEFAULT")
        end

        def stop
          @running = false
        end

        def running?
          @running
        end

        # Emit notifications/tools/list_changed (2026-07-28: consumed by
        # clients on the shared stdio channel or on a subscriptions/listen
        # stream). Call these after your tool/resource/prompt sets change.
        # Safe to call from any thread; writes are flushed immediately.
        def notify_tools_list_changed
          send_notification("notifications/tools/list_changed")
        end

        def notify_resources_list_changed
          send_notification("notifications/resources/list_changed")
        end

        def notify_prompts_list_changed
          send_notification("notifications/prompts/list_changed")
        end

        private

        def graceful_shutdown
          @shutdown_requested = true
          # Close stdin to unblock $stdin.gets so the signal handler
          # returns promptly and the process exits cleanly.
          $stdin.close rescue nil
        end

        def process_line(line)
          msg = JSON.parse(line, symbolize_names: true)
          handle_message(msg)
        rescue JSON::ParserError => e
          send_error(nil, -32700, "Parse error: #{e.message}")
        end

        def handle_message(msg)
          method = msg[:method]
          id = msg[:id]
          params = msg[:params] || {}
          has_id = msg.key?(:id)

          # Stateless (2026-07-28) requests carry the protocol version in
          # `_meta` instead of an `initialize` handshake. Detecting it here
          # unlocks all handlers without the legacy @initialized gate.
          if (meta_version = meta_protocol_version(params))
            @protocol_version = meta_version
            @stateless = true
            @initialized = true
            debug_log "Stateless request (protocol #{meta_version})"
          end

          case method
          when "initialize"
            handle_initialize(id, params)
          when "server/discover"
            handle_discover(id)
          when "notifications/initialized"
            @initialized = true
            debug_log "Client initialized"
          when "tools/list"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_tools_list(id)
          when "tools/call"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_tool_call(id, params)
          when "resources/list"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_resources_list(id)
          when "resources/read"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_resource_read(id, params)
          when "resources/templates/list"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_resources_templates_list(id)
          when "prompts/list"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_prompts_list(id)
          when "prompts/get"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_prompt_get(id, params)
          when "ping"
            # ping was removed in 2026-07-28; legacy clients still use it.
            if stateless_mode?
              send_error(id, -32601, "Method not found: ping") if has_id
            else
              send_result(id, {}) if has_id
            end
          else
            debug_log "Unknown method: #{method}"
            send_error(id, -32601, "Method not found: #{method}") if has_id
          end
        end

        # server/discover (2026-07-28): advertise supported protocol versions,
        # capabilities, and identity. Clients call it before anything else to
        # select a version (or as a backward-compat probe on stdio).
        def handle_discover(id)
          send_result(id, {
            protocolVersions: Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS,
            capabilities: @capabilities,
            serverInfo: { name: @name, version: Ask::MCP::VERSION }
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
              version: Ask::MCP::VERSION
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
            code = stateless_mode? ? -32_602 : Native::Messages::ErrorCodes::RESOURCE_NOT_FOUND
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
          # 2026-07-28: all results carry `resultType`. Legacy peers tolerate
          # the field, but we only add it for stateless peers to keep the
          # legacy wire output unchanged.
          result = result.merge(resultType: "complete") if stateless_mode?
          $stdout.puts({ jsonrpc: "2.0", id: id, result: result }.to_json)
        end

        # Write a server→client notification (no id). stdout is sync'd in
        # #start, so this is safe to call from any thread.
        def send_notification(method, params = {})
          msg = { jsonrpc: "2.0", method: method }
          msg[:params] = params unless params.empty?
          $stdout.puts(msg.to_json)
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
          $stdout.puts({ jsonrpc: "2.0", id: id, error: { code: code, message: message } }.to_json)
        end

        def debug_log(msg)
          return unless @debug
          ts = Time.now.strftime("%H:%M:%S.%L")
          $stderr.puts "[#{ts}] [ask-mcp] #{msg}"
        end

        def trim_cache
          return if @result_cache.size <= MAX_RESULT_CACHE
          @result_cache.shift(@result_cache.size - MAX_RESULT_CACHE)
        end
      end
    end
  end
end
