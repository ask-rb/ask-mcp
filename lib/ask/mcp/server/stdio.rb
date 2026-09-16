# frozen_string_literal: true

module Ask
  module MCP
    class Server
      # MCP server over the stdio transport.
      #
      # Reads newline-delimited JSON-RPC on stdin and writes replies to
      # stdout as they are produced. All message handling lives in Core;
      # this class adds the read loop and the stdout writer.
      class Stdio < Core
        # Deprecated: use Ask::MCP::PROTOCOL_VERSION (the canonical constant).
        PROTOCOL_VERSION = Ask::MCP::PROTOCOL_VERSION

        def initialize(**options)
          super
          @running = false
          @shutdown_requested = false
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

        # Static stdio peers have no request/response framing, so each message
        # is written the moment the Core produces it.
        def deliver(message)
          $stdout.puts(JSON.generate(message))
        end

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
          send_error(nil, Native::Messages::ErrorCodes::PARSE_ERROR, "Parse error: #{e.message}")
        end
      end
    end
  end
end
