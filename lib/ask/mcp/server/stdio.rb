# frozen_string_literal: true

require "json"
require "timeout"

module Ask
  module MCP
    class Server
      # MCP server over stdio transport.
      class Stdio
        MAX_RESULT_CACHE = 100

        attr_reader :name, :tools, :capabilities, :resources, :prompts

        def initialize(name:, tools: [], capabilities: {}, resources: {}, prompts: {},
                       debug: false, tool_timeout: nil)
          @name = name
          @capabilities = capabilities
          @resources = resources
          @prompts = prompts
          @debug = debug
          @tool_timeout = tool_timeout

          @adapter = Adapters::ToolServer.new(tools || [])
          @initialized = false
          @running = false
          @shutdown_requested = false
          @result_cache = {}
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

          case method
          when "initialize"
            handle_initialize(id, params)
          when "notifications/initialized"
            @initialized = true
            debug_log "Client initialized"
          when "tools/list"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_tools_list(id)
          when "tools/call"
            return send_error(id, -32000, "Server not initialized") unless @initialized
            handle_tool_call(id, params)
          when "ping"
            send_result(id, {}) if has_id
          else
            debug_log "Unknown method: #{method}"
            send_error(id, -32601, "Method not found: #{method}") if has_id
          end
        end

        def handle_initialize(id, params)
          @initialized = true
          client_version = params[:protocolVersion] || PROTOCOL_VERSION
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
          send_result(id, { tools: defs })
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

        def send_result(id, result)
          $stdout.puts({ jsonrpc: "2.0", id: id, result: result }.to_json)
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
