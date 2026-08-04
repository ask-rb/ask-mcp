if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/vendor/"
    track_files "lib/**/*.rb"
  end
end

# frozen_string_literal: true

require "ostruct"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ask/mcp"
require "minitest/autorun"
require "mocha/minitest" if Gem.loaded_specs.key?("mocha")

# Polls the block until it returns truthy or the deadline passes. Use this
# instead of a fixed `sleep N` before asserting on subprocess output — fixed
# sleeps flake under CI load, polling is robust. Returns the block's value or
# nil if the deadline passed.
def wait_until(timeout: 5, interval: 0.05)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    value = yield
    return value if value
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return nil if remaining <= 0
    sleep [interval, remaining].min
  end
end
