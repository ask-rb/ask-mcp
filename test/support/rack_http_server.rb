# frozen_string_literal: true

require "socket"
require "stringio"

# A single-threaded HTTP/1.1 server just large enough to serve a Rack app to a
# real client: one request per connection, then close. Dependency-free, so the
# interop test needs no web server gem and no fixed port.
class RackHTTPServer
  attr_reader :port

  def initialize(app)
    @app = app
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { accept_loop }
    @thread.abort_on_exception = true
  end

  def url
    "http://127.0.0.1:#{@port}/mcp"
  end

  def shutdown
    @thread.kill
    @server.close
  rescue IOError
    nil
  end

  private

  def accept_loop
    loop { handle(@server.accept) }
  end

  def handle(socket)
    request_line = socket.gets
    return socket.close if request_line.nil?

    method, = request_line.split
    headers = read_headers(socket)
    body = read_body(socket, headers["content-length"].to_i)

    status, response_headers, response_body = @app.call(rack_env(method, headers, body))
    write_response(socket, status, response_headers, response_body.join)
  rescue StandardError
    socket.close
  ensure
    socket.close unless socket.closed?
  end

  def read_headers(socket)
    headers = {}
    while (line = socket.gets)
      line = line.strip
      break if line.empty?

      name, value = line.split(": ", 2)
      headers[name.downcase] = value.to_s
    end
    headers
  end

  def read_body(socket, length)
    length.positive? ? socket.read(length).to_s : ""
  end

  def rack_env(method, headers, body)
    {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => "/mcp",
      "CONTENT_TYPE" => headers["content-type"],
      "HTTP_ACCEPT" => headers["accept"],
      "HTTP_MCP_METHOD" => headers["mcp-method"],
      "HTTP_MCP_NAME" => headers["mcp-name"],
      "HTTP_MCP_PROTOCOL_VERSION" => headers["mcp-protocol-version"],
      "rack.input" => StringIO.new(body)
    }
  end

  def write_response(socket, status, headers, payload)
    socket.write("HTTP/1.1 #{status} #{reason(status)}\r\n")
    headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("Content-Length: #{payload.bytesize}\r\n")
    socket.write("Connection: close\r\n\r\n")
    socket.write(payload)
  end

  def reason(status)
    { 200 => "OK", 202 => "Accepted", 400 => "Bad Request", 401 => "Unauthorized",
      403 => "Forbidden", 404 => "Not Found", 405 => "Method Not Allowed" }.fetch(status, "OK")
  end
end
