# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "badline"
require "timecop"
require "tmpdir"

# Whether the host refuses a file its mode doesn't grant. Root, or a process
# holding CAP_DAC_OVERRIDE, reads and writes past the mode anyway.
def file_permissions_enforced?
  Dir.mktmpdir do |dir|
    file = File.join(dir, "probe")
    File.write(file, "")
    File.chmod(0o000, file)
    File.chmod(0o555, dir)
    File.read(file)
    File.write(File.join(dir, "new"), "")
    false
  rescue Errno::EACCES
    true
  ensure
    File.chmod(0o755, dir)
  end
end

RSpec.configure do |config|
  # Examples tagged :slow boot the whole machine and are skipped by default.
  # Run them with `bundle exec rspec --tag slow`.
  config.filter_run_excluding :slow

  # Examples tagged :file_permissions chmod a file away from the host and
  # expect the failure, so they're skipped where the mode isn't enforced.
  config.filter_run_excluding :file_permissions unless file_permissions_enforced?

  # The 90% coverage floor only applies when every spec file ran unfiltered,
  # so single-file and focused runs aren't failed by it.
  config.before(:suite) do
    all_specs = Dir[File.join(__dir__, "**/*_spec.rb")].map { |f| File.expand_path(f) }
    full_run = config.inclusion_filter.empty? && config.files_to_run.sort == all_specs.sort
    SimpleCov.minimum_coverage 90 if full_run
  end
end
