# frozen_string_literal: true

module Ask
  module MCP
    module Transport
      class SSE
        attr_reader :url

        def initialize(url, options = {})
          @url = url
          @options = options
          @running = false
          @buffer = +""
          @message_handlers = []
          @http = nil
          @response = nil
          @post_url = nil
          @reconnect_delay = options[:reconnect_delay] || 1.0
          @max_reconnect_delay = options[:max_reconnect_delay] || 30.0
          @reconnect_jitter = options[:reconnect_jitter] || 0.1
          @max_retries = options[:max_retries] || 5
          @retries = 0
        end

        def on_message(&block)
          @message_handlers << block
        end

        def start
          require "httpx"

          @running = true
          @retries = 0
          @post_url = nil
          connect_stream
          self
        end

        def stop
          @running = false
          @response&.close
          @http&.close
        end

        def send(message)
          require "httpx"

          data = message.is_a?(String) ? message : message.to_json
          target = @post_url || @url

          headers = { "Content-Type" => "application/json" }
          headers.merge!(@options[:headers]) if @options[:headers]

          http = HTTPX.with(headers:)
          response = http.post(target, body: data)

          unless response.status == 200 || response.status == 202 || response.status == 204
            raise ConnectionError, "Failed to send message: #{response.status} #{response.body.to_s}"
          end

          response
        rescue HTTPX::Error => e
          raise ConnectionError, "Failed to send message: #{e.message}"
        end

        def running?
          @running
        end

        def shutdown
          stop
        end

        private

        def connect_stream
          return unless @running

          @http = HTTPX.with(timeout: { request_timeout: @options[:timeout] || 300 })
          @http = @http.with(headers: @options[:headers]) if @options[:headers]

          @response = @http.get(@url)

          unless @response.status == 200
            raise ConnectionError, "SSE connection failed: #{@response.status}"
          end

          @retries = 0
          @current_event = nil
          @buffer = +""

          @response.body.each do |chunk|
            process_chunk(chunk)
          end
        rescue HTTPX::Error, ConnectionError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
          handle_disconnect(e)
        end

        def process_chunk(chunk)
          @buffer << chunk
          while (line = @buffer.slice!(/\A.*\n/))
            line = line.strip
            next if line.empty?

            if line.start_with?("event: ")
              @current_event = line[7..]
            elsif line.start_with?("data: ")
              data_line = line[6..]

              case @current_event
              when "endpoint"
                @post_url = data_line.strip
                @current_event = nil
              when "message", nil
                begin
                  message = Native::Messages::Parser.parse(data_line)
                  @message_handlers.each { |handler| handler.call(message) }
                rescue JSON::ParserError
                  # Skip non-JSON data
                end
                @current_event = nil
              else
                @current_event = nil
              end
            end
          end
        end

        def handle_disconnect(error)
          return unless @running

          @retries += 1

          if @retries > @max_retries
            @message_handlers.each { |h| h.call(error) }
            return
          end

          delay = calculate_backoff
          sleep(delay)
          connect_stream
        end

        def calculate_backoff
          delay = [@reconnect_delay * (2 ** (@retries - 1)), @max_reconnect_delay].min
          jitter = delay * @reconnect_jitter * (rand - 0.5) * 2
          delay + jitter
        end
      end
    end
  end
end
