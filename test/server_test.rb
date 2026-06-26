# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class ServerTest < Minitest::Test
  def test_server_construction
    tool = Ask::MCP::Tool.new(name: "ping", description: "Ping pong")
    server = Ask::MCP::Server.new(
      name: "test-server",
      version: "1.0.0",
      capabilities: { tools: {} },
      tools: { "ping" => tool }
    )
    assert_equal "test-server", server.name
    assert_equal "1.0.0", server.version
    assert_equal ["ping"], server.tool_names
    assert server.capabilities.key?(:tools)
  end

  def test_server_to_h
    server = Ask::MCP::Server.new(
      name: "empty-server",
      capabilities: { tools: {} }
    )
    h = server.to_h
    assert_equal "empty-server", h[:name]
    assert_equal [], h[:tools]
  end

  def test_server_with_resources
    resource = Ask::MCP::Resource.new(uri: "file:///tmp/test.txt", name: "Test")
    server = Ask::MCP::Server.new(
      name: "resource-server",
      resources: { "file:///tmp/test.txt" => resource }
    )
    assert_equal ["file:///tmp/test.txt"], server.resource_uris
  end

  def test_server_with_prompts
    prompt = Ask::MCP::Prompt.new(name: "greet", description: "Greeting prompt")
    server = Ask::MCP::Server.new(
      name: "prompt-server",
      prompts: { "greet" => prompt }
    )
    assert_equal ["greet"], server.prompt_names
  end

  def test_server_to_h_includes_all_elements
    tool = Ask::MCP::Tool.new(name: "ping", description: "Ping")
    resource = Ask::MCP::Resource.new(uri: "file:///tmp/test.txt", name: "Test")
    prompt = Ask::MCP::Prompt.new(name: "greet")
    server = Ask::MCP::Server.new(
      name: "full-server",
      version: "2.0.0",
      capabilities: { tools: {}, resources: {}, prompts: {} },
      tools: { "ping" => tool },
      resources: { "file:///tmp/test.txt" => resource },
      prompts: { "greet" => prompt }
    )
    h = server.to_h
    assert_equal "full-server", h[:name]
    assert_equal "2.0.0", h[:version]
    assert_equal 1, h[:tools].size
    assert_equal 1, h[:resources].size
    assert_equal 1, h[:prompts].size
  end

  def test_server_default_version
    server = Ask::MCP::Server.new(name: "default")
    assert_equal "0.1.0", server.version
  end

  def test_server_empty_tools
    server = Ask::MCP::Server.new(name: "no-tools")
    assert_empty server.tool_names
  end
end

class ServerStartStdioTest < Minitest::Test
  def test_start_stdio_accepts_required_params
    assert_respond_to Ask::MCP::Server, :start_stdio

    script = File.expand_path("support/test_start_stdio.rb", __dir__)
    stdin, _stdout, _stderr, wait_thr = Open3.popen3(
      { "BUNDLE_GEMFILE" => File.expand_path("../Gemfile", __dir__) },
      "ruby", script
    )
    stdin.puts('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}')
    stdin.flush
    stdin.close
    exit_status = wait_thr.value
    assert exit_status.success?, "start_stdio server should exit cleanly"
  end

  def test_start_stdio_with_debug
    script = File.expand_path("support/test_start_stdio_debug.rb", __dir__)
    stdin, _stdout, stderr, wait_thr = Open3.popen3(
      { "BUNDLE_GEMFILE" => File.expand_path("../Gemfile", __dir__) },
      "ruby", script
    )
    stdin.puts('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}')
    stdin.flush
    stdin.close

    stderr_output = +""
    begin
      while (char = stderr.read_nonblock(4096))
        stderr_output << char
      end
    rescue IO::WaitReadable, EOFError
      begin
        stderr_output << stderr.read
      rescue
      end
    rescue IOError
    end

    exit_status = wait_thr.value
    assert exit_status.success?
    assert_match(/Server starting/, stderr_output, "Debug mode should log to stderr")
  ensure
    stdin&.close rescue nil
  end
end
