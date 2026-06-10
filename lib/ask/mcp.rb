require "json"
require "securerandom"
require_relative "mcp/version"

module Ask
  module MCP
    autoload :Client, "ask/mcp/client"
    autoload :Server, "ask/mcp/server"
    autoload :Tool, "ask/mcp/tool"
    autoload :Resource, "ask/mcp/resource"
    autoload :Prompt, "ask/mcp/prompt"
    autoload :Transport, "ask/mcp/transport"

    module Transport
      autoload :Stdio, "ask/mcp/transport/stdio"
      autoload :SSE, "ask/mcp/transport/sse"
      autoload :StreamableHTTP, "ask/mcp/transport/streamable_http"
    end

    module Auth
      autoload :OAuth, "ask/mcp/auth/oauth"
      autoload :Token, "ask/mcp/auth/token"
    end

    class Error < StandardError; end
    class ConnectionError < Error; end
    class ProtocolError < Error; end
    class AuthError < Error; end

    class << self
      def connect(transport, options = {})
        Client.new(transport, options)
      end

      def from_stdio(command, args = [], options = {})
        transport = Transport::Stdio.new(command, args, options)
        Client.new(transport)
      end

      def from_sse(url, options = {})
        transport = Transport::SSE.new(url, options)
        Client.new(transport)
      end

      def from_http(url, options = {})
        transport = Transport::StreamableHTTP.new(url, options)
        Client.new(transport)
      end
    end
  end
end
