# frozen_string_literal: true

module Ask
  module MCP
    module Auth
      class Token
        attr_reader :token, :scheme

        def initialize(token, scheme: "Bearer")
          @token = token
          @scheme = scheme
        end

        def apply(headers = {})
          headers.merge("Authorization" => "#{@scheme} #{@token}")
        end

        def to_s
          "#{@scheme} #{@token[0..7]}..."
        end
      end
    end
  end
end
