# frozen_string_literal: true

module Ask
  module MCP
    module Native
      # JSON-RPC 2.0 message types for the Model Context Protocol.
      module Messages
        JSON_RPC_VERSION = "2.0"

        class Request
          attr_reader :id, :method, :params

          def initialize(method:, params: nil, id: nil)
            @id = id || SecureRandom.uuid
            @method = method
            @params = params
          end

          def to_h
            h = {
              jsonrpc: JSON_RPC_VERSION,
              id: @id,
              method: @method
            }
            h[:params] = @params if @params
            h
          end

          def to_json(*args)
            to_h.to_json(*args)
          end
        end

        class Notification
          attr_reader :method, :params

          def initialize(method:, params: nil)
            @method = method
            @params = params
          end

          def to_h
            h = {
              jsonrpc: JSON_RPC_VERSION,
              method: @method
            }
            h[:params] = @params if @params
            h
          end

          def to_json(*args)
            to_h.to_json(*args)
          end
        end

        class Response
          attr_reader :id, :result, :error

          def initialize(id:, result: nil, error: nil)
            @id = id
            @result = result
            @error = error
          end

          def success?
            @error.nil?
          end

          def to_h
            h = { jsonrpc: JSON_RPC_VERSION, id: @id }
            if @error
              h[:error] = {
                code: @error[:code],
                message: @error[:message]
              }
              h[:error][:data] = @error[:data] if @error[:data]
            else
              h[:result] = @result || {}
            end
            h
          end

          def to_json(*args)
            to_h.to_json(*args)
          end
        end

        module Parser
          def self.parse(json_string)
            data = JSON.parse(json_string, symbolize_names: true)
            return data unless data.is_a?(Hash)

            if data.key?(:id) && (data.key?(:result) || data.key?(:error))
              Response.new(
                id: data[:id],
                result: data[:result],
                error: data[:error]
              )
            elsif data.key?(:method) && data.key?(:id)
              Request.new(
                method: data[:method],
                params: data[:params],
                id: data[:id]
              )
            elsif data.key?(:method) && !data.key?(:id)
              Notification.new(
                method: data[:method],
                params: data[:params]
              )
            else
              data
            end
          end

          def self.parse_response(json_string)
            msg = parse(json_string)
            raise ProtocolError, "Expected a Response, got #{msg.class}" unless msg.is_a?(Response)
            msg
          end

          def self.parse_request(json_string)
            msg = parse(json_string)
            raise ProtocolError, "Expected a Request, got #{msg.class}" unless msg.is_a?(Request)
            msg
          end
        end

        # Standard JSON-RPC error codes
        module ErrorCodes
          PARSE_ERROR      = -32700
          INVALID_REQUEST  = -32600
          METHOD_NOT_FOUND = -32601
          INVALID_PARAMS   = -32602
          INTERNAL_ERROR   = -32603

          # MCP-specific error codes
          TOOL_NOT_FOUND      = -32000
          RESOURCE_NOT_FOUND  = -32001
          PROMPT_NOT_FOUND    = -32002
          AUTH_ERROR          = -32003
          CONNECTION_ERROR    = -32004
          TIMEOUT_ERROR       = -32005

          ERROR_MESSAGES = {
            PARSE_ERROR      => "Parse error",
            INVALID_REQUEST  => "Invalid request",
            METHOD_NOT_FOUND => "Method not found",
            INVALID_PARAMS   => "Invalid params",
            INTERNAL_ERROR   => "Internal error",
            TOOL_NOT_FOUND   => "Tool not found",
            RESOURCE_NOT_FOUND => "Resource not found",
            PROMPT_NOT_FOUND => "Prompt not found",
            AUTH_ERROR       => "Authentication error",
            CONNECTION_ERROR => "Connection error",
            TIMEOUT_ERROR    => "Timeout error"
          }.freeze
        end
      end
    end
  end
end
