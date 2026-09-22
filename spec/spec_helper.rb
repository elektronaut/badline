# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "badline"
require "timecop"

RSpec.configure do |config|
  # Examples tagged :slow boot the whole machine and are skipped by default.
  # Run them with `bundle exec rspec --tag slow`.
  config.filter_run_excluding :slow

  # The 90% coverage floor only applies when every spec file ran unfiltered,
  # so single-file and focused runs aren't failed by it.
  config.before(:suite) do
    all_specs = Dir[File.join(__dir__, "**/*_spec.rb")].map { |f| File.expand_path(f) }
    full_run = config.inclusion_filter.empty? && config.files_to_run.sort == all_specs.sort
    SimpleCov.minimum_coverage 90 if full_run
  end
end
