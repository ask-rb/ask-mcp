# frozen_string_literal: true

module Ask
  module MCP
    module Transport
      class StreamableHTTP
        attr_reader :url

        def initialize(url, options = {})
          @url = url
          @options = options
          @running = false
          @message_handlers = []
          @http = nil
          @session_id = nil
        end

        def on_message(&block)
          @message_handlers << block
        end

        def start
          require "httpx"

          headers = { "Content-Type" => "application/json" }
          headers["Accept"] = "text/event-stream" if @options[:stream]
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
          @http&.close
        end

        def send(message)
          data = message.is_a?(String) ? message : message.to_json

          if @options[:stream]
            send_streaming(data)
          else
            send_request_response(data)
          end
        rescue HTTPX::Error => e
          raise ConnectionError, "HTTP error: #{e.message}"
        end

        def running?
          @running
        end

        def shutdown
          stop
        end

        private

        def send_request_response(data)
          response = @http.post(@url, body: data)
          status = response.status

          if status == 200 || status == 202
            body = response.body.to_s
            if body && !body.empty?
              message = Native::Messages::Parser.parse(body)
              @message_handlers.each { |handler| handler.call(message) }
            end
          elsif status == 204
            # No content — nothing to process
          else
            raise ConnectionError, "HTTP #{status}: #{response.body.to_s[0..200]}"
          end

          response
        end

        def send_streaming(data)
          response = @http.post(@url, body: data)

          unless response.status == 200
            raise ConnectionError, "HTTP #{response.status}: #{response.body.to_s[0..200]}"
          end

          buffer = +""
          response.body.each do |chunk|
            buffer << chunk
            while (line = buffer.slice!(/\A.*\n/))
              line = line.strip
              next if line.empty?

              if line.start_with?("data: ")
                data_line = line[6..]
                begin
                  message = Native::Messages::Parser.parse(data_line)
                  @message_handlers.each { |handler| handler.call(message) }
                rescue JSON::ParserError
                  # Skip non-JSON data lines
                end
              end
            end
          end
        end
      end
    end
  end
end
