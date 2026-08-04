# frozen_string_literal: true

module Ask
  module MCP
    class Client
      # Deprecated: use Ask::MCP::PROTOCOL_VERSION (the canonical constant).
      # Kept as an alias so existing consumers don't break.
      PROTOCOL_VERSION = Ask::MCP::PROTOCOL_VERSION

      attr_reader :transport, :capabilities, :server_info

      def initialize(transport, options = {})
        @transport = transport
        @options = options
        @capabilities = {}
        @server_info = {}
        @tools_cache = nil
        @resources_cache = nil
        @prompts_cache = nil
        @pending_requests = {}
        @pending_mutex = Mutex.new
        @pending_condition = ConditionVariable.new
        @request_handlers = {}
        @next_id = 0
        @initialized = false
        # Negotiated protocol version; nil until start() resolves it.
        @protocol_version = nil
        @stateless = false
      end

      def start
        @transport.on_message { |message| handle_message(message) }
        @transport.start
        negotiate_protocol
        self
      end

      def stop
        @transport.stop
        @initialized = false
      end

      def tools
        return @tools_cache if @tools_cache && !@options[:no_cache]

        response = send_request("tools/list")
        tools = (response[:tools] || []).map { |t| Tool.from_h(t) }
        tools = reject_invalid_mcp_header_tools(tools)
        @tools_cache = index_by_name(tools)
      end

      def resources
        return @resources_cache if @resources_cache && !@options[:no_cache]

        response = send_request("resources/list")
        resources = (response[:resources] || []).map { |r| Resource.from_h(r) }
        @resources_cache = index_by_uri(resources)
      end

      def prompts
        return @prompts_cache if @prompts_cache && !@options[:no_cache]

        response = send_request("prompts/list")
        prompts = (response[:prompts] || []).map { |p| Prompt.from_h(p) }
        @prompts_cache = index_by_name(prompts)
      end

      def call_tool(name, arguments = {})
        if @options[:validate] && @tools_cache
          tool = @tools_cache[name]
          if tool && tool.input_schema && !tool.input_schema.empty?
            Validator.new(tool.input_schema).validate!(arguments)
          end
        end
        headers = mcp_param_headers(name, arguments)
        response = send_request("tools/call", { name: name, arguments: arguments }, headers: headers)
        response[:content] || response
      end

      def read_resource(uri)
        response = send_request("resources/read", { uri: uri })
        response[:contents] || response
      end

      def get_prompt(name, arguments = {})
        response = send_request("prompts/get", { name: name, arguments: arguments })
        response[:messages] || response
      end

      def initialized?
        @initialized
      end

      # Register a handler for a server-initiated request (a JSON-RPC Request
      # the server sends to the client, such as elicitation/create or
      # sampling/createMessage). The handler receives the request params and
      # must return the result hash to send back. The handler runs on the
      # transport reader thread, so long-blocking handlers block message
      # processing — return promptly.
      def on_request(method, &handler)
        @request_handlers[method] = handler
      end

      # Handle a server request for user input (client/elicitation, 2025-06-18+).
      # The handler receives the elicitation params (including the Elicitation
      # schema with titled/untitled, single/multi-select enums and default
      # values in 2025-11-25) and returns an ElicitationResponse hash, e.g.
      #   { message: "42" }
      # or structured content. Declare client support via
      #   Ask::MCP::Client.new(transport, client_capabilities: { elicitation: {} })
      def on_elicitation(&handler)
        on_request("elicitation/create", &handler)
      end

      # Handle a sampling request (client/sampling). The handler receives the
      # CreateMessageRequest params — including `tools` and `toolChoice` when
      # the server offers tool calling (2025-11-25, SEP-1577) — and returns a
      # CreateMessageResult hash, e.g.
      #   { role: "assistant", content: { type: "text", text: "..." } }
      # Declare client support via
      #   Ask::MCP::Client.new(transport, client_capabilities: { sampling: {} })
      def on_sampling(&handler)
        on_request("sampling/createMessage", &handler)
      end

      # Open a long-lived notification stream (2026-07-28 subscriptions/listen).
      # `notifications` is a filter Hash, e.g.
      #   { toolsListChanged: true, resourceSubscriptions: ["file:///x"] }
      # Notifications flow into the client's message handling (which resets
      # caches on list_changed). Only supported on transports that implement
      # #listen (StreamableHTTP).
      def listen(notifications)
        @transport.listen(notifications)
      end

      private

      # Resolve the protocol version to speak with the server (2026-07-28
      # stateless negotiation). Tries `server/discover` first: a server that
      # answers with a supported version list we intersect goes stateless
      # (no initialize handshake); anything else falls back to the legacy
      # `initialize` handshake.
      def negotiate_protocol
        if discover_server
          if @stateless
            # 2026-07-28 stateless peer: no initialize handshake.
            @initialized = true
            reset_caches
            debug "Stateless mode (protocol #{@protocol_version})"
          else
            # Server is a legacy revision (≤ 2025-11-25): it still requires
            # the initialize handshake. discover already filled in server_info
            # and capabilities; initialize refines them.
            initialize_session
          end
        else
          initialize_session
        end
        # Streamable HTTP mirrors the negotiated version into the
        # MCP-Protocol-Version header on every POST.
        @transport.protocol_version = @protocol_version if @transport.respond_to?(:protocol_version=)
      end

      def discover_server
        response = send_request_raw("server/discover", {}, timeout: 5)
        return false unless response.success?

        result = response.result
        supported = result[:protocolVersions] || result["protocolVersions"] || []
        chosen = Ask::MCP::SUPPORTED_PROTOCOL_VERSIONS.reverse.find { |v| supported.include?(v) }
        return false unless chosen

        @protocol_version = chosen
        @stateless = chosen == Ask::MCP::LATEST_PROTOCOL_VERSION
        @server_info = result[:serverInfo] || result["serverInfo"] || {}
        @capabilities = result[:capabilities] || result["capabilities"] || {}
        true
      rescue StandardError
        false
      end

      def reset_caches
        @tools_cache = nil
        @resources_cache = nil
        @prompts_cache = nil
      end

      def meta_params
        meta = {
          Native::Messages::Meta::PROTOCOL_VERSION_KEY => @protocol_version,
          Native::Messages::Meta::CLIENT_CAPABILITIES_KEY => @options[:client_capabilities] || {},
          Native::Messages::Meta::CLIENT_INFO_KEY => { name: "ask-mcp", version: Ask::MCP::VERSION }
        }
        # Optional extra `_meta` fields — e.g. OpenTelemetry trace context
        # (traceparent/tracestate/baggage) via
        #   Client.new(transport, meta: TraceContext.from_headers(rack_env))
        meta.merge!(@options[:meta]) if @options[:meta]
        { _meta: meta }
      end

      # Mirror x-mcp-header-annotated tool parameters into Mcp-Param-{Name}
      # HTTP headers (2026-07-28, SEP-2243). Only applies on transports that
      # support it (StreamableHTTP). Values are encoded per the spec; integer
      # values outside the JavaScript safe range cannot be represented safely
      # and their headers are omitted.
      def mcp_param_headers(tool_name, arguments)
        return {} unless @transport.is_a?(Transport::StreamableHTTP)
        tool = @tools_cache && @tools_cache[tool_name]
        return {} unless tool && tool.input_schema

        props = tool.input_schema[:properties] || tool.input_schema["properties"] || {}
        props.each_with_object({}) do |(prop_name, prop_schema), headers|
          header_name = prop_schema[:'x-mcp-header'] || prop_schema["x-mcp-header"]
          next unless header_name
          value = arguments[prop_name] || arguments[prop_name.to_s]
          next if value.nil?
          next if value.is_a?(Integer) && !XMcpHeader.safe_integer?(value)
          headers["Mcp-Param-#{header_name}"] = @transport.encode_header_value(value)
        end
      end

      # Streamable HTTP clients MUST reject tool definitions with invalid
      # x-mcp-header annotations, excluding the tool from tools/list
      # (2026-07-28, SEP-2243). Other transports ignore the annotations.
      def reject_invalid_mcp_header_tools(tools)
        return tools unless @transport.is_a?(Transport::StreamableHTTP)

        tools.reject do |tool|
          reason = XMcpHeader.invalid_reason(tool.input_schema)
          next false unless reason

          warn "[ask-mcp][client] rejecting tool #{tool.name} from tools/list: #{reason}"
          true
        end
      end

      def next_id
        @pending_mutex.synchronize do
          @next_id += 1
        end
      end

      def initialize_session
        response = send_request_raw("initialize", {
          protocolVersion: @protocol_version || Ask::MCP::PROTOCOL_VERSION,
          capabilities: @options[:client_capabilities] || {},
          clientInfo: {
            name: "ask-mcp",
            version: Ask::MCP::VERSION
          }
        })

        unless response.success?
          raise ProtocolError, "Initialize failed: #{response.error[:message]}"
        end

        result = response.result
        @server_info = result[:serverInfo] || {}
        @capabilities = result[:capabilities] || {}
        @protocol_version = result[:protocolVersion] || Ask::MCP::PROTOCOL_VERSION

        send_notification("notifications/initialized")
        @initialized = true

        reset_caches
      end

      def debug(msg)
        warn "[ask-mcp][client] #{msg}" if @options[:debug]
      end

      def send_request(method, params = {}, headers: {})
        response = send_request_raw(method, params, headers: headers)
        raise ProtocolError, "Request failed: #{response.error[:message]}" unless response.success?
        response.result
      end

      def send_request_raw(method, params = {}, timeout: nil, headers: {})
        params = params.merge(meta_params) if @stateless
        request = Native::Messages::Request.new(method:, params:, id: next_id)
        wait_for_response(request, timeout: timeout, headers: headers)
      end

      def send_notification(method, params = {})
        notification = Native::Messages::Notification.new(method:, params:)
        @transport.send(notification)
      end

      # Multi Round-Trip Requests (2026-07-28, SEP-2322): how many times the
      # client may retry a request after an InputRequiredResult before giving up.
      MAX_MRTR_ROUND_TRIPS = 5

      def wait_for_response(request, timeout: nil, headers: {})
        timeout ||= @options[:timeout] || 60
        round_trips = 0

        loop do
          response = send_and_wait(request, timeout, headers: headers)
          return response unless input_required?(response)

          round_trips += 1
          if round_trips > MAX_MRTR_ROUND_TRIPS
            raise ProtocolError, "MRTR exceeded #{MAX_MRTR_ROUND_TRIPS} round trips"
          end

          result = response.result
          input_responses = resolve_input_requests(result[:inputRequests] || result["inputRequests"] || {})
          request = build_retry_request(request, result, input_responses)
        end
      end

      # Send a single request and wait for its response.
      def send_and_wait(request, timeout, headers: {})
        # Register the pending request BEFORE sending to avoid race
        @pending_mutex.synchronize do
          @pending_requests[request.id] = true
        end

        @transport.send(request, headers)

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        @pending_mutex.synchronize do
          loop do
            val = @pending_requests[request.id]
            if val.is_a?(Native::Messages::Response)
              @pending_requests.delete(request.id)
              return val
            end

            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if remaining <= 0
              @pending_requests.delete(request.id)
              raise ConnectionError, "Request timed out after #{timeout}s"
            end

            @pending_condition.wait(@pending_mutex, remaining)
          end
        end
      end

      # An InputRequiredResult only occurs in the stateless (2026-07-28) mode.
      def input_required?(response)
        @stateless && response.success? && response.result.is_a?(Hash) &&
          response.result[:resultType] == "input_required"
      end

      # Resolve each server inputRequest (elicitation/create, sampling/
      # createMessage, roots/list) through the registered on_request handlers.
      # Returns the InputResponses map keyed by the server's identifiers.
      def resolve_input_requests(input_requests)
        return {} if input_requests.nil? || input_requests.empty?

        input_requests.each_with_object({}) do |(key, req), responses|
          method = req[:method] || req["method"]
          handler = @request_handlers[method]
          unless handler
            raise ProtocolError, "MRTR: no handler registered for #{method} (inputRequest #{key})"
          end
          responses[key] = handler.call(req[:params] || req["params"] || {})
        end
      end

      # Build the MRTR retry: same method, a NEW id, the original params plus
      # inputResponses and — if the server sent one — the opaque requestState
      # echoed verbatim (clients MUST NOT inspect or modify it).
      def build_retry_request(request, result, input_responses)
        retry_params = (request.params || {}).dup
        retry_params[:inputResponses] = input_responses
        state = result[:requestState] || result["requestState"]
        retry_params[:requestState] = state if state
        Native::Messages::Request.new(method: request.method, params: retry_params, id: next_id)
      end

      def handle_message(message)
        case message
        when Native::Messages::Response
          handle_response(message)
        when Native::Messages::Request
          handle_request(message)
        when Native::Messages::Notification
          handle_notification(message)
        when Exception
          raise ConnectionError, "Transport error: #{message.message}"
        end
      end

      def handle_response(response)
        @pending_mutex.synchronize do
          if @pending_requests.key?(response.id)
            @pending_requests[response.id] = response
            @pending_condition.broadcast
          end
        end
      end

      def handle_request(request)
        handler = @request_handlers[request.method]
        response = if handler
                     Native::Messages::Response.new(id: request.id, result: handler.call(request.params || {}))
                   else
                     Native::Messages::Response.new(
                       id: request.id,
                       error: {
                         code: Native::Messages::ErrorCodes::METHOD_NOT_FOUND,
                         message: "Method not implemented: #{request.method}"
                       }
                     )
                   end
        @transport.send(response)
      end

      def handle_notification(notification)
        case notification.method
        when "notifications/tools/list_changed"
          @tools_cache = nil
        when "notifications/resources/list_changed"
          @resources_cache = nil
        when "notifications/prompts/list_changed"
          @prompts_cache = nil
        end
      end

      def index_by_name(objects)
        objects.each_with_object({}) { |obj, hash| hash[obj.name] = obj }
      end

      def index_by_uri(objects)
        objects.each_with_object({}) { |obj, hash| hash[obj.uri] = obj }
      end
    end
  end
end
