module Ask
  module MCP
    class Client
      attr_reader :transport, :capabilities

      def initialize(transport, options = {})
        @transport = transport
        @capabilities = {}
        @tools = {}
        @resources = {}
        @prompts = {}
      end

      def start
        transport.start
        initialize_session
        self
      end

      def stop
        transport.stop
      end

      def tools
        @tools
      end

      def resources
        @resources
      end

      def prompts
        @prompts
      end

      def call_tool(name, arguments = {})
        raise NotImplementedError, "Implement me — see GOAL.md for details"
      end

      def read_resource(uri)
        raise NotImplementedError, "Implement me — see GOAL.md for details"
      end

      def get_prompt(name, arguments = {})
        raise NotImplementedError, "Implement me — see GOAL.md for details"
      end

      private

      def initialize_session
        raise NotImplementedError, "Implement me — see GOAL.md for details"
      end
    end
  end
end
