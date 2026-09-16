# frozen_string_literal: true

module Ask
  module MCP
    class Server
      attr_reader :name, :version, :capabilities, :tools, :resources, :prompts

      def initialize(name:, version: "0.1.0", capabilities: {}, tools: {}, resources: {}, prompts: {})
        @name = name
        @version = version
        @capabilities = capabilities
        @tools = tools
        @resources = resources
        @prompts = prompts
      end

      def tool_names
        @tools.keys
      end

      def resource_uris
        @resources.keys
      end

      def prompt_names
        @prompts.keys
      end

      def to_h
        {
          name: @name,
          version: @version,
          capabilities: @capabilities,
          tools: @tools.values.map(&:to_h),
          resources: @resources.values.map(&:to_h),
          prompts: @prompts.values.map(&:to_h)
        }
      end

      # Start an MCP server over stdio.
      # Blocking — designed to be the last line of an entry-point script.
      #
      # @param name [String] server name
      # @param version [String, nil] server version reported in serverInfo;
      #   defaults to the ask-mcp version when nil
      # @param tools [Array<#call, #name, #description, #params_schema>] tool instances to expose
      # @param capabilities [Hash] MCP capabilities (default: { tools: {} })
      # @param resources [Hash{String => #to_h, #content}] uri → resource objects
      # @param prompts [Hash{String => #to_h, #messages}] name → prompt objects
      # @param debug [Boolean] enable stderr debug logging
      def self.start_stdio(name:, version: nil, tools: [], capabilities: { tools: {} }, resources: {},
                            prompts: {}, resource_templates: {}, debug: false)
        Stdio.new(name: name, version: version, tools: tools, capabilities: capabilities,
                  resources: resources, prompts: prompts,
                  resource_templates: resource_templates, debug: debug).start
      end

      # Build a Rack application serving MCP over the stateless Streamable
      # HTTP transport (2026-07-28). Mount it wherever Rack runs:
      #
      #   mount Ask::MCP::Server.rack_app(name: "anychat", tools: [...]) => "/mcp"
      #
      # Accepts the same tool/resource/prompt options as .start_stdio, plus:
      #
      # @param authenticate [#call, nil] receives the Rack env per request and
      #   returns the caller's identity; a nil return answers 401
      # @param context [#call, nil] derives the value passed to a callable
      #   `tools` when no `authenticate` is given (defaults to the Rack env)
      # @return [Server::HTTP] a Rack application
      def self.rack_app(**options)
        HTTP.new(**options)
      end
    end
  end
end

# Load Server subclasses after the Server class is defined
require_relative "server/core"
require_relative "server/stdio"
require_relative "server/http"
