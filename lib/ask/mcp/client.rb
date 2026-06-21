# frozen_string_literal: true

module Ask
  module MCP
    class Client
      PROTOCOL_VERSION = "0.1.0"

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
        @next_id = 0
        @initialized = false
      end

      def start
        @transport.on_message { |message| handle_message(message) }
        @transport.start
        initialize_session
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
        response = send_request("tools/call", name: name, arguments: arguments)
        response[:content] || response
      end

      def read_resource(uri)
        response = send_request("resources/read", uri: uri)
        response[:contents] || response
      end

      def get_prompt(name, arguments = {})
        response = send_request("prompts/get", name: name, arguments: arguments)
        response[:messages] || response
      end

      def initialized?
        @initialized
      end

      private

      def next_id
        @pending_mutex.synchronize do
          @next_id += 1
        end
      end

      def initialize_session
        response = send_request_raw("initialize", {
          protocolVersion: PROTOCOL_VERSION,
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

        send_notification("notifications/initialized")
        @initialized = true

        @tools_cache = nil
        @resources_cache = nil
        @prompts_cache = nil
      end

      def send_request(method, params = {})
        response = send_request_raw(method, params)
        raise ProtocolError, "Request failed: #{response.error[:message]}" unless response.success?
        response.result
      end

      def send_request_raw(method, params = {})
        request = Native::Messages::Request.new(method:, params:, id: next_id)
        wait_for_response(request)
      end

      def send_notification(method, params = {})
        notification = Native::Messages::Notification.new(method:, params:)
        @transport.send(notification)
      end

      def wait_for_response(request)
        # Register the pending request BEFORE sending to avoid race
        @pending_mutex.synchronize do
          @pending_requests[request.id] = true
        end

        @transport.send(request)

        timeout = @options[:timeout] || 60
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
        response = Native::Messages::Response.new(
          id: request.id,
          error: {
            code: Native::Messages::ErrorCodes::METHOD_NOT_FOUND,
            message: "Method not implemented: #{request.method}"
          }
        )
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
