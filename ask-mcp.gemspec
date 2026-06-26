require_relative "lib/ask/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "ask-mcp"
  spec.version = Ask::MCP::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Model Context Protocol (MCP) client and server for Ruby"
  spec.description = "Connect to MCP servers via stdio, SSE, and Streamable HTTP transports. " \
                     "Run as an MCP server to expose Ask::Tool instances. " \
                     "Discover tools, resources, and prompts. OAuth 2.1 authentication."
  spec.homepage = "https://github.com/ask-rb/ask-mcp"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "docs/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "httpx", "~> 1.4"
  spec.add_dependency "json-schema", "~> 5.0"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 3.1"
  spec.add_development_dependency "rake", "~> 13.0"
end
