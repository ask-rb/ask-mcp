require "json"
require "securerandom"
require_relative "mcp/version"

module Ask
  module MCP
    # The MCP protocol revision this gem implements and advertises.
    # Single source of truth — Client and Server::Stdio both reference this
    # so the advertised version can never drift between the two sides.
    #
    # `PROTOCOL_VERSION` is the legacy default (stateful `initialize`
    # handshake). `SUPPORTED_PROTOCOL_VERSIONS` is what the server advertises
    # via `server/discover`; `LATEST_PROTOCOL_VERSION` is the stateless
    # 2026-07-28 revision that clients and servers negotiate to.
    PROTOCOL_VERSION = "2025-06-18"
    LATEST_PROTOCOL_VERSION = "2026-07-28"
    SUPPORTED_PROTOCOL_VERSIONS = [PROTOCOL_VERSION, "2025-11-25", LATEST_PROTOCOL_VERSION].freeze

    autoload :Client, "ask/mcp/client"
    autoload :Server, "ask/mcp/server"
    autoload :Tool, "ask/mcp/tool"
    autoload :Resource, "ask/mcp/resource"
    autoload :Prompt, "ask/mcp/prompt"
    autoload :Validator, "ask/mcp/validator"
    autoload :XMcpHeader, "ask/mcp/x_mcp_header"
    autoload :TraceContext, "ask/mcp/trace_context"

    module Native
      autoload :Messages, "ask/mcp/native/messages"
    end

    module Transport
      autoload :Stdio, "ask/mcp/transport/stdio"
      autoload :SSE, "ask/mcp/transport/sse"
      autoload :StreamableHTTP, "ask/mcp/transport/streamable_http"
    end

    module Auth
      autoload :OAuth, "ask/mcp/auth/oauth"
      autoload :Token, "ask/mcp/auth/token"
      autoload :ClientIdMetadataDocument, "ask/mcp/auth/client_id_metadata_document"
    end

    module Adapters
      autoload :AskTool, "ask/mcp/adapters/ask_tool"
      autoload :ToolServer, "ask/mcp/adapters/tool_server"
    end

    class Error < StandardError; end
    class ConnectionError < Error; end
    class ProtocolError < Error; end
    class AuthError < Error; end
    class ValidationError < Error; end

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

      # Validate tool arguments against a JSON Schema input schema
      def validate!(schema, arguments)
        Validator.new(schema).validate!(arguments)
      end
    end
  end
end
