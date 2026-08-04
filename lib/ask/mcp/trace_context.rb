# frozen_string_literal: true

module Ask
  module MCP
    # OpenTelemetry trace context propagation via MCP `_meta` (2026-07-28,
    # SEP-414). The convention reserves three `_meta` keys — `traceparent`,
    # `tracestate`, `baggage` — so traces can span the client/server boundary.
    module TraceContext
      KEYS = %w[traceparent tracestate baggage].freeze

      module_function

      # Extract trace context from arbitrary HTTP-style headers, matching
      # names case-insensitively and accepting Rack's HTTP_* env convention.
      #
      #   TraceContext.from_headers(rack_env)
      #   # => { "traceparent" => "00-...", "tracestate" => "..." }
      def from_headers(headers)
        headers.each_with_object({}) do |(name, value), out|
          key = name.to_s.downcase
          key = key.delete_prefix("http_") if key.start_with?("http_")
          next unless KEYS.include?(key)

          out[key] = value.to_s
        end
      end

      # Extract trace context from an MCP request's `_meta` hash (keys may be
      # symbols or strings, as the JSON parser symbolizes keys).
      def from_meta(meta)
        meta = meta || {}
        KEYS.each_with_object({}) do |key, out|
          value = meta[key] || meta[key.to_sym]
          out[key] = value.to_s if value
        end
      end
    end
  end
end
