# frozen_string_literal: true

require "base64"

module Ask
  module MCP
    module Transport
      # Streamable HTTP transport (2026-07-28 shape).
      #
      # Every JSON-RPC message is its own HTTP POST to the single MCP
      # endpoint. Each POST carries the mirrored request-metadata headers:
      #   - MCP-Protocol-Version (matching the body's `_meta` protocolVersion)
      #   - Mcp-Method (the JSON-RPC method)
      #   - Mcp-Name (params.name / params.uri for tools/call, resources/read,
      #     prompts/get)
      # The server answers with either a single `application/json` object or
      # an SSE stream scoped to the request; the client must handle both,
      # chosen per response by Content-Type.
      #
      # Protocol-level sessions, the GET stream endpoint, and Last-Event-ID
      # resumability were removed in 2026-07-28 and are not implemented.
      class StreamableHTTP
        attr_reader :url
        # Set by the client after negotiation; sent as MCP-Protocol-Version.
        attr_accessor :protocol_version

        def initialize(url, options = {})
          @url = url
          @options = options
          @running = false
          @message_handlers = []
          @http = nil
          @protocol_version = nil
          @listen_thread = nil
        end

        def on_message(&block)
          @message_handlers << block
        end

        def start
          require "httpx"

          headers = { "Content-Type" => "application/json" }
          headers["Accept"] = "application/json, text/event-stream"
          headers.merge!(@options[:headers]) if @options[:headers]

          @http = HTTPX.with(
            headers:,
            timeout: { request_timeout: @options[:timeout] || 30 }
          )
          @running = true
          self
        end

        def stop
          @running = false
          @listen_thread&.kill
          @http&.close
        end

        # Send a JSON-RPC message. `extra_headers` (e.g. Mcp-Param-* mirrored
        # from tool parameters) are merged into the request metadata headers.
        def send(message, extra_headers = {})
          data = message.is_a?(String) ? message : message.to_json
          headers = request_headers(message).merge(extra_headers)
          response = @http.post(@url, body: data, headers: headers)
          handle_response(response)
        rescue HTTPX::Error => e
          raise ConnectionError, "HTTP error: #{e.message}"
        end

        # Open a long-lived notification stream via subscriptions/listen
        # (2026-07-28). The response SSE stream stays open; delivered
        # notifications (e.g. notifications/tools/list_changed,
        # notifications/resources/updated) are passed to on_message handlers.
        # The notifications filter is a Hash like
        #   { toolsListChanged: true, resourceSubscriptions: ["uri"] }
        # Close the stream by calling #close_listen or #stop.
        def listen(notifications)
          require "httpx"

          request = Native::Messages::Request.new(
            method: "subscriptions/listen",
            params: { notifications: notifications },
            id: @options[:listen_id] || 1
          )
          headers = request_headers(request)
          response = @http.post(@url, body: request.to_json, headers: headers)

          unless response.status == 200
            raise ConnectionError, "HTTP #{response.status}: #{response.body.to_s[0..200]}"
          end

          @listen_thread = Thread.new { read_sse_stream(response) }
          self
        end

        def close_listen
          @listen_thread&.kill
          @listen_thread = nil
        end

        def running?
          @running
        end

        def shutdown
          stop
        end

        # Encode a value for use as an HTTP header value per the spec: plain
        # visible ASCII passes through; anything else (non-ASCII, control
        # characters, leading/trailing whitespace, or a value matching the
        # Base64 sentinel pattern) is encoded as =?base64?...?=.
        def encode_header_value(value)
          str = value.to_s
          header_safe?(str) ? str : "=?base64?#{Base64.strict_encode64(str)}?="
        end

        private

        def request_headers(message)
          headers = { "Accept" => "application/json, text/event-stream" }

          if message.is_a?(Native::Messages::Request) || message.is_a?(Native::Messages::Notification)
            headers["Mcp-Method"] = message.method
            headers["MCP-Protocol-Version"] = @protocol_version if @protocol_version
            if %w[tools/call resources/read prompts/get].include?(message.method) && message.params
              value = message.params[:name] || message.params[:uri] ||
                      message.params["name"] || message.params["uri"]
              headers["Mcp-Name"] = encode_header_value(value) if value
            end
          end

          headers
        end

        def handle_response(response)
          status = response.status
          if status == 202
            # Notification accepted, no body.
            return response
          end
          unless status == 200
            raise ConnectionError, "HTTP #{status}: #{response.body.to_s[0..200]}"
          end

          content_type = response.headers["content-type"].to_s
          if content_type.include?("text/event-stream")
            read_sse_stream(response)
          else
            body = response.body.to_s
            if body && !body.empty?
              message = Native::Messages::Parser.parse(body)
              @message_handlers.each { |handler| handler.call(message) }
            end
          end

          response
        end

        # Read an SSE stream, delivering each `data:` payload as a parsed
        # message. Lines beginning with a colon are SSE comments (keep-alive)
        # and are ignored. Returns when the server closes the stream.
        def read_sse_stream(response)
          buffer = +""
          response.body.each do |chunk|
            buffer << chunk
            while (line = buffer.slice!(/\A.*\n/))
              line = line.strip
              next if line.empty? || line.start_with?(":")

              if line.start_with?("data: ")
                begin
                  message = Native::Messages::Parser.parse(line[6..])
                  @message_handlers.each { |handler| handler.call(message) }
                rescue JSON::ParserError
                  # Skip non-JSON data lines
                end
              end
            end
          end
        end

        def header_safe?(str)
          return false if str.start_with?("=?base64?") && str.end_with?("?=")
          return false unless str == str.strip
          str.each_char.all? { |c| c.ord >= 0x20 && c.ord <= 0x7E }
        end
      end
    end
  end
end
