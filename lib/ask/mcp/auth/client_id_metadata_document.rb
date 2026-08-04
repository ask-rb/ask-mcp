# frozen_string_literal: true

require "uri"

module Ask
  module MCP
    module Auth
      # OAuth Client ID Metadata Documents (2026-07-28, SEP-991) — the
      # recommended client registration mechanism, replacing the deprecated
      # Dynamic Client Registration Protocol (RFC 7591).
      #
      # A client_id is an HTTPS URL pointing to a JSON document describing the
      # client; the authorization server fetches and validates it on demand.
      # Because the document is self-hosted, URL-based client IDs are portable
      # across authorization servers — no re-registration needed when the
      # server changes.
      module ClientIdMetadataDocument
        # Fields every metadata document MUST include.
        REQUIRED_FIELDS = %w[client_id client_name redirect_uris].freeze
        # OIDC application types (native = desktop/mobile/CLI/localhost web).
        APPLICATION_TYPES = %w[native web].freeze

        module_function

        # Build a metadata document hash. `client_id` must be an https URL
        # with a path component; `redirect_uris` must be a non-empty array.
        # Extra keyword args are included verbatim (string keys).
        def build(client_id:, client_name:, redirect_uris:, application_type: "native", **extra)
          {
            "client_id" => client_id,
            "client_name" => client_name,
            "redirect_uris" => redirect_uris,
            "application_type" => application_type
          }.merge(extra.transform_keys(&:to_s))
        end

        # Whether the client_id has the required URL form: https scheme with
        # a path component (e.g. https://example.com/client.json).
        def valid_client_id_url?(client_id)
          uri = URI.parse(client_id.to_s)
          uri.scheme == "https" && !uri.path.to_s.empty? && uri.path != "/"
        rescue URI::InvalidURIError
          false
        end

        # Validate a fetched document. Returns nil when valid, or a reason
        # string. When `document_url` is given, the document's client_id MUST
        # match it exactly.
        def invalid_reason(document, document_url: nil)
          return "metadata document must be a JSON object" unless document.is_a?(Hash)

          missing = REQUIRED_FIELDS.reject { |f| document[f] || document[f.to_sym] }
          return "missing required fields: #{missing.join(', ')}" unless missing.empty?

          client_id = (document["client_id"] || document[:client_id]).to_s
          if document_url && client_id != document_url
            return "client_id #{client_id.inspect} does not match document URL #{document_url.inspect}"
          end
          return "client_id must be an https URL with a path" unless valid_client_id_url?(client_id)

          redirect_uris = document["redirect_uris"] || document[:redirect_uris]
          return "redirect_uris must be a non-empty array" unless redirect_uris.is_a?(Array) && !redirect_uris.empty?

          app_type = document["application_type"] || document[:application_type]
          if app_type && !APPLICATION_TYPES.include?(app_type.to_s)
            return "invalid application_type #{app_type.inspect}"
          end

          nil
        end
      end
    end
  end
end
