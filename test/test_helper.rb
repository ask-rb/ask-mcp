# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "minitest/autorun"
require "mocha/minitest" if Gem.loaded_specs.key?("mocha")
