# frozen_string_literal: true

require "open3"

module Ask
  module MCP
    module Transport
      class Stdio
        attr_reader :command, :args, :pid

        def initialize(command, args = [], options = {})
          @command = command
          @args = args
          @options = options
          @pid = nil
          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thr = nil
          @buffer = +""
          @message_handlers = []
          @running = false
          @mutex = Mutex.new
        end

        def on_message(&block)
          @message_handlers << block
        end

        def start
          env = @options[:env] || {}
          workdir = @options[:workdir]

          cmd = build_command
          @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(env, *cmd, chdir: workdir || Dir.pwd)
          @pid = @wait_thr.pid
          @running = true

          start_reader
          self
        end

        def stop
          @running = false
          @stdin&.close unless @stdin&.closed?
          @stdout&.close unless @stdout&.closed?
          @stderr&.close unless @stderr&.closed?
          @wait_thr&.value
        rescue Errno::EPIPE, Errno::ECHILD
          # Process already exited
        end

        def send(message)
          data = message.is_a?(String) ? message : message.to_json
          @mutex.synchronize do
            @stdin&.puts(data)
            @stdin&.flush
          end
        rescue Errno::EPIPE, IOError => e
          raise ConnectionError, "Failed to send message: #{e.message}"
        end

        def running?
          @running && @wait_thr&.alive?
        end

        def shutdown
          stop
        end

        private

        def build_command
          if @command.is_a?(Array)
            @command
          else
            [@command] + @args
          end
        end

        def start_reader
          @reader_thread = Thread.new do
            read_partial_line(@stdout)
          rescue IOError, Errno::EPIPE, Errno::EBADF => e
            @running = false
            notify_error(e)
          end
        end

        def read_partial_line(io)
          while @running && (char = io.getc)
            @buffer << char
            if @buffer.end_with?("\n")
              line = @buffer.strip
              @buffer = +""
              next if line.empty?

              process_line(line)
            end
          end
        rescue IOError, Errno::EPIPE, Errno::EBADF
          @running = false
        end

        def process_line(line)
          message = Native::Messages::Parser.parse(line)
          @message_handlers.each { |handler| handler.call(message) }
        rescue JSON::ParserError => e
          # Ignore non-JSON output (e.g., stderr mixed in)
        rescue ProtocolError => e
          notify_error(e)
        end

        def notify_error(error)
          @message_handlers.each do |handler|
            handler.call(error) if error.is_a?(Exception)
          end
        end
      end
    end
  end
end
