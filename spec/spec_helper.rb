# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "badline"
require "timecop"

RSpec.configure do |config|
  # Examples tagged :slow boot the whole machine and are skipped by default.
  # Run them with `bundle exec rspec --tag slow`.
  config.filter_run_excluding :slow
end
