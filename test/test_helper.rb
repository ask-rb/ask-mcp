if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/vendor/"
    track_files "lib/**/*.rb"
  end
end

# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "minitest/autorun"
require "mocha/minitest" if Gem.loaded_specs.key?("mocha")
