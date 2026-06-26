# frozen_string_literal: true

require "json"

module Ask
  module MCP
    class Server
      # MCP server over stdio transport.
      #
      # Reads JSON-RPC 2.0 messages from stdin and writes responses to stdout.
      # Designed to be spawned as a child process by MCP clients (Codex Desktop,
      # Claude Code, etc.) with command/args config.
      #
      # Usage:
      #   Server::Stdio.new(name: "my-server", tools: my_tools).start
      #
      class Stdio
        PROTOCOL_VERSION = "0.1.0"

        attr_reader :name, :tools, :capabilities, :resources, :prompts

        def initialize(name:, tools: [], capabilities: {}, resources: {}, prompts: {}, debug: false)
          @name = name
          @capabilities = capabilities
          @resources = resources
          @prompts = prompts
          @debug = debug

          @adapter = Adapters::AskToolServer.new(tools || [])
          @initialized = false
          @running = false
        end

        # Start the server (blocking). Processes stdin until EOF.
        def start
          @running = true
          $stdout.sync = true

          debug_log "Server starting: #{@name} (PID #{Process.pid})"
          debug_log "Tools: #{@adapter.definitions.map { |d| d[:name] }.join(', ')}"

          while @running && (line = $stdin.gets)
            line = line.strip
            next if line.empty?

            process_line(line)
          end

          debug_log "stdin closed — exiting"
        rescue Errno::EBADF, IOError
          # stdin closed externally
        ensure
          @running = false
        end

        # Stop the server (non-blocking, closes stdin to unblock the read loop).
        def stop
          @running = false
        end

        # Is the server still running?
        def running?
          @running
        end

        private

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
          else
            debug_log "Unknown method: #{method}"
            send_error(id, -32601, "Method not found: #{method}") if has_id
          end
        end

        def handle_initialize(id, _params)
          @initialized = true
          debug_log "Handling initialize (id=#{id.inspect})"
          send_result(id, {
            protocolVersion: PROTOCOL_VERSION,
            capabilities: @capabilities,
            serverInfo: {
              name: @name,
              version: Ask::MCP::VERSION
            }
          })
          debug_log "Initialize complete"
        end

        def handle_tools_list(id)
          debug_log "Handling tools/list (id=#{id.inspect})"
          defs = @adapter.definitions
          debug_log "tools/list returning #{defs.length} tool definitions"
          send_result(id, { tools: defs })
        end

        def handle_tool_call(id, params)
          tool_name = params[:name].to_s
          arguments = params[:arguments] || {}

          debug_log "Handling tools/call: #{tool_name} (id=#{id.inspect})"

          result = @adapter.call(tool_name, arguments)
          send_result(id, result)
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
      end
    end
  end
end
