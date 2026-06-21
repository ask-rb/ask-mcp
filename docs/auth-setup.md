# Authentication Setup

ask-mcp supports two authentication methods for connecting to MCP servers that
require authorization: **Token-based auth** and **OAuth 2.1**.

## Token Authentication

Use for servers with simple API tokens or bearer tokens.

```ruby
require "ask/mcp"

token = Ask::MCP::Auth::Token.new("my-api-token")
headers = token.apply({})
# => { "Authorization" => "Bearer my-api-token" }

# Custom scheme
basic = Ask::MCP::Auth::Token.new("base64encoded", scheme: "Basic")
headers = basic.apply({})
# => { "Authorization" => "Basic base64encoded" }
```

### Applying to Transports

```ruby
# With SSE transport
token = Ask::MCP::Auth::Token.new("my-token")
client = Ask::MCP.from_sse("https://mcp.example.com/sse",
  headers: token.apply({})
)

# With Streamable HTTP transport
client = Ask::MCP.from_http("https://mcp.example.com/mcp",
  headers: token.apply({})
)
```

## OAuth 2.1

Use for servers that implement the OAuth 2.1 authorization framework.

### Client Credentials Flow

For server-to-server communication where you have a client secret:

```ruby
oauth = Ask::MCP::Auth::OAuth.new(
  client_id: "your-client-id",
  client_secret: "your-client-secret",
  token_url: "https://auth.example.com/token",
  scopes: ["mcp"]
)

oauth.authenticate!
headers = oauth.apply({})
# => { "Authorization" => "Bearer eyJhbGciOi..." }
```

### Authorization Code Flow

For user-facing applications that need delegated access:

```ruby
oauth = Ask::MCP::Auth::OAuth.new(
  client_id: "your-client-id",
  token_url: "https://auth.example.com/token",
  auth_url: "https://auth.example.com/authorize",
  redirect_uri: "http://localhost:3000/callback",
  scopes: ["mcp"]
)

# This opens the authorization URL for the user to approve
oauth.authenticate!
```

### Token Refresh

OAuth tokens are automatically refreshed when expired:

```ruby
oauth.authenticate!
# ... use the token ...

# When the token expires, refresh it:
oauth.refresh!
```

## With ask-auth

If you're using `ask-auth` for credential resolution:

```ruby
require "ask-auth"
require "ask/mcp"

# Resolve credentials from ask-auth chain (env → file → rails)
token = Ask::Auth.resolve(:mcp_token)
if token
  auth = Ask::MCP::Auth::Token.new(token)
  client = Ask::MCP.from_sse("https://mcp.example.com/sse",
    headers: auth.apply({})
  )
end
```

For OAuth credentials:

```ruby
client_id = Ask::Auth.resolve(:mcp_client_id)
client_secret = Ask::Auth.resolve(:mcp_client_secret)
token_url = Ask::Auth.resolve(:mcp_token_url)

oauth = Ask::MCP::Auth::OAuth.new(
  client_id: client_id,
  client_secret: client_secret,
  token_url: token_url
)
oauth.authenticate!
```

## Configuration File

You can store credentials in `~/.ask/credentials.yml` for use with ask-auth:

```yaml
mcp_token: "my-mcp-server-token"
mcp_client_id: "my-client-id"
mcp_client_secret: "my-client-secret"
mcp_token_url: "https://auth.example.com/token"
```

## Environment Variables

ask-auth detects these environment variables automatically:

```
MCP_TOKEN=my-token
MCP_CLIENT_ID=my-client-id
MCP_CLIENT_SECRET=my-client-secret
MCP_TOKEN_URL=https://auth.example.com/token
```
