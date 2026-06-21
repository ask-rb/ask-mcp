# frozen_string_literal: true

module Ask
  module MCP
    # Validates tool call arguments against JSON Schema input schemas.
    # Uses the json-schema gem to validate arguments before sending to a server.
    class Validator
      class ValidationError < Error; end

      def initialize(schema)
        @schema = schema
      end

      def validate!(arguments)
        return true if @schema.nil? || @schema.empty?

        require "json-schema"

        string_schema = deep_stringify_keys(@schema)
        data = arguments.is_a?(Hash) ? deep_stringify_keys(arguments) : arguments

        errors = JSON::Validator.fully_validate(string_schema, data)
        if errors.any?
          raise ValidationError, "Validation failed: #{errors.join(", ")}"
        end

        true
      end

      def valid?(arguments)
        validate!(arguments)
        true
      rescue ValidationError
        false
      end

      private

      def deep_stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify_keys(v) }
        when Array
          obj.map { |v| deep_stringify_keys(v) }
        else
          obj
        end
      end
    end
  end
end
