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

        errors = validate_with_dialect_fallback(string_schema, data)
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

      # The json-schema gem implements drafts 1-7 but not JSON Schema 2020-12,
      # which MCP 2025-11-25 declares as the default dialect. Most 2020-12
      # schemas only use keywords shared with earlier drafts, so validating
      # them still works — but the gem rejects the 2020-12 metaschema itself
      # ("Schema not found: .../draft/2020-12/schema"). When a schema declares
      # the 2020-12 dialect, strip the $schema key and retry.
      def validate_with_dialect_fallback(schema, data)
        JSON::Validator.fully_validate(schema, data)
      rescue JSON::Schema::SchemaError, JSON::Schema::JsonParseError => e
        if schema["$schema"].to_s.include?("2020-12")
          cleaned = schema.dup
          cleaned.delete("$schema")
          JSON::Validator.fully_validate(cleaned, data)
        else
          raise e
        end
      end

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
