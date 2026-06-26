#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "timeout"
require "fileutils"

# Helper to interact with an MCP server over stdio.
# Spawns the server as a subprocess and provides helpers
# for sending JSON-RPC messages and reading responses.
class MCPServerHarness
  TIMEOUT = 5

  attr_reader :stdin, :stdout, :stderr, :wait_thr, :pid
  attr_accessor :buffer

  def initialize(command, args = [], env: {})
    @command = command
    @args = args
    @env = env
    @buffer = +""
    @stderr_buffer = +""
  end

  def start
    merged_env = @env.dup
    merged_env["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __dir__)

    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(merged_env, @command, *@args)
    @pid = @wait_thr.pid
    @stdin.sync = true
    self
  end

  def stop
    @stdin&.close unless @stdin&.closed?
    @stdout&.close unless @stdout&.closed?
    @stderr&.close unless @stderr&.closed?
    @wait_thr&.value
  rescue Errno::EPIPE, Errno::ECHILD
    # already closed
  end

  def send_request(method, params = nil, id: 1)
    msg = { jsonrpc: "2.0", id: id, method: method }
    msg[:params] = params if params
    @stdin.puts(msg.to_json)
    @stdin.flush
  end

  def send_notification(method, params = nil)
    msg = { jsonrpc: "2.0", method: method }
    msg[:params] = params if params
    @stdin.puts(msg.to_json)
    @stdin.flush
  end

  def read_response(timeout: TIMEOUT)
    Timeout.timeout(timeout) do
      loop do
        char = @stdout.getc
        return nil if char.nil?
        @buffer << char
        if @buffer.end_with?("\n")
          line = @buffer.strip
          @buffer = +""
          next if line.empty?

          parsed = JSON.parse(line, symbolize_names: true)
          if parsed.key?(:id)
            return parsed
          end
        end
      end
    end
  rescue Timeout::Error
    raise "Timeout waiting for response after #{timeout}s\nBuffer: #{@buffer.inspect}"
  end

  def initialize_session
    send_request("initialize", {
      protocolVersion: "0.1.0",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0" }
    })
    resp = read_response
    raise "Initialize failed: #{resp[:error]}" if resp[:error]
    send_notification("notifications/initialized")
    resp
  end

  def list_tools
    send_request("tools/list")
    read_response
  end

  def call_tool(name, arguments = {})
    send_request("tools/call", { name: name, arguments: arguments }, id: 3)
    read_response
  end

  def read_stderr
    output = +""
    begin
      while (char = @stderr.read_nonblock(4096))
        output << char
      end
    rescue IO::WaitReadable, EOFError, Errno::EAGAIN, Errno::EWOULDBLOCK
      # no more data right now
    rescue IOError
      # stream closed
    end
    @stderr_buffer << output unless output.empty?
    output
  end

  def stderr_output
    read_stderr
    @stderr_buffer
  end

  def wait_for_stderr(pattern, timeout: 3)
    Timeout.timeout(timeout) do
      loop do
        output = read_stderr
        return output if output.match?(pattern)
        sleep 0.05
      end
    end
  rescue Timeout::Error
    raise "Timeout waiting for #{pattern.inspect} on stderr\nAccumulated: #{@stderr_buffer.inspect}"
  end
end
