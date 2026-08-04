# frozen_string_literal: true

module Ask
  module MCP
    # Validation of `x-mcp-header` annotations in tool inputSchemas
    # (2026-07-28, SEP-2243).
    #
    # Servers MAY designate tool parameters to be mirrored into HTTP headers
    # via an `x-mcp-header` extension property. Clients using the Streamable
    # HTTP transport MUST reject a tool definition whose annotations violate
    # the constraints below (rejection = exclude the tool from tools/list);
    # clients on other transports (stdio, SSE) MAY ignore the annotations.
    module XMcpHeader
      # RFC 9110 field-name token characters (1*tchar).
      TOKEN_RE = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/
      # Primitive types that may carry an x-mcp-header annotation.
      PRIMITIVE_TYPES = %w[string integer boolean].freeze
      # JavaScript safe integer range.
      JS_SAFE_MIN = -(2**53) + 1
      JS_SAFE_MAX = 2**53 - 1

      module_function

      # Returns the reason the tool definition's x-mcp-header annotations are
      # invalid, or nil if the definition is valid (or has no annotations).
      def invalid_reason(schema)
        seen = {}
        find_invalid(schema, seen, tainted: false)
      end

      # Whether an integer value is representable as a safe header value.
      def safe_integer?(value)
        value.is_a?(Integer) && value.between?(JS_SAFE_MIN, JS_SAFE_MAX)
      end

      # Depth-first walk. An annotation is valid only if the chain from the
      # schema root to it passes solely through `properties` keys; every other
      # container keyword (items, oneOf/anyOf/allOf/not, if/then/else, $ref,
      # $defs, ...) taints the path, which is exactly the spec's "statically
      # reachable" rule.
      def find_invalid(node, seen, tainted:)
        return nil unless node.is_a?(Hash)

        annotation = node[:'x-mcp-header'] || node["x-mcp-header"]
        if annotation
          return "x-mcp-header must not appear under non-properties keywords" if tainted

          reason = annotation_error(annotation, node)
          return reason if reason

          key = annotation.to_s.downcase
          return "duplicate x-mcp-header #{annotation.inspect} (case-insensitive)" if seen[key]

          seen[key] = true
        end

        node.each do |key, value|
          if key.to_s == "properties" && value.is_a?(Hash)
            # The allowed step: descending through a `properties` key does not
            # taint the chain.
            value.each_value do |sub|
              reason = find_invalid(sub, seen, tainted: tainted)
              return reason if reason
            end
          elsif value.is_a?(Hash)
            reason = find_invalid(value, seen, tainted: true)
            return reason if reason
          elsif value.is_a?(Array)
            value.each do |item|
              next unless item.is_a?(Hash)
              reason = find_invalid(item, seen, tainted: true)
              return reason if reason
            end
          end
        end

        nil
      end

      def annotation_error(header_name, prop)
        name = header_name.to_s
        return "x-mcp-header must not be empty" if name.empty?
        return "x-mcp-header #{name.inspect} contains invalid characters" unless name.match?(TOKEN_RE)

        type = prop[:type] || prop["type"]
        unless PRIMITIVE_TYPES.include?(type.to_s)
          return "x-mcp-header #{name.inspect} must be on a primitive type (string/integer/boolean), got #{type.inspect}"
        end

        nil
      end
      private_class_method :find_invalid, :annotation_error
    end
  end
end
