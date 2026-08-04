# frozen_string_literal: true

# An in-memory transport for testing Ask::MCP::Client without spawning a
# subprocess. Records every message sent (for assertions on the wire), and
# can auto-reply to requests with canned results keyed by method name.
#
# @example
#   transport = RecordingTransport.new(
#     "initialize" => { serverInfo: { name: "mock", version: "1.0" }, capabilities: {} }
#   )
#   client = Ask::MCP::Client.new(transport)
#   client.start
#   init = transport.sent.find { |m| m.method == "initialize" }
#   assert_equal "2025-06-18", init.params[:protocolVersion]
class RecordingTransport
  attr_reader :sent

  # @param replies [Hash{String => Hash, Proc}] canned results per request
  #   method. A Proc receives the sent message and returns the result hash.
  # @param auto_reply [Proc, nil] optional override that receives every sent
  #   message and returns a result hash or nil to skip replying.
  def initialize(replies = {}, &auto_reply)
    @replies = replies
    @auto_reply = auto_reply
    @sent = []
    @on_message = nil
    @started = false
  end

  def on_message(&block)
    @on_message = block
  end

  def start
    @started = true
  end

  def stop
    @started = false
  end

  def running?
    @started
  end

  def send(msg, _headers = {})
    @sent << msg
    # Only JSON-RPC Requests (method + id) can be replied to. Notifications
    # have no id; Responses sent by the client must not be replied to.
    return unless msg.is_a?(Ask::MCP::Native::Messages::Request)

    reply = @auto_reply&.call(msg)
    reply ||= @replies[msg.method]
    if reply.nil?
      # Simulate a legacy server: unknown methods error with METHOD_NOT_FOUND.
      # This is what makes the client's server/discover probe fall back to
      # the initialize handshake in tests without configuration.
      deliver(Ask::MCP::Native::Messages::Response.new(
        id: msg.id,
        error: { code: -32_601, message: "Method not found: #{msg.method}" }
      ))
      return
    end

    reply = reply.call(msg) if reply.respond_to?(:call)
    deliver(Ask::MCP::Native::Messages::Response.new(id: msg.id, result: reply))
  end

  # Deliver an inbound message (e.g. a server-initiated Request) as if it
  # arrived from the wire. Used to test client handling of server requests.
  def inject(message)
    deliver(message)
  end

  private

  def deliver(msg)
    @on_message&.call(msg)
  end
end
