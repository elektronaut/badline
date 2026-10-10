# frozen_string_literal: true

# The SID testprogs runner. bin/sidtests runs SIDTests.main and documents
# its options.

lib = File.expand_path("../../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "badline"
require "fileutils"
require_relative "cli"
require_relative "forked_boot"
require_relative "sidtests_machine"

module SIDTests
  ROOT = File.expand_path("../../vendor/VICE-testprogs/SID", __dir__)
  TESTLIST = File.expand_path("../../vendor/VICE-testprogs/testbench/c64-testlist.in", __dir__)

  module_function

  # Test names mapped to their cycle budget after boot.
  def tests(sid_model = :mos6581)
    File.readlines(TESTLIST).filter_map { |line| parse(line, sid_model) }.to_h
  end

  # A testlist row is "dir/,prg,type,cycles[,option...]". Only the exitcode
  # rows under SID/ are kept, as [name, cycles]: those tagged for the chip
  # the machine is built with, and the untagged ones, which were written for
  # either. Rows that mount a disk image are left out, since the runner only
  # injects the .prg.
  def parse(line, sid_model = :mos8580)
    dir, prg, type, cycles, *options = line.strip.split(",")
    return unless dir&.start_with?("../SID/") && type == "exitcode"
    return if options.include?(sid_model == :mos8580 ? "sid-old" : "sid-new")
    return if options.any? { it.start_with?("mount") }

    ["#{dir.delete_prefix('../SID/')}#{prg}", Integer(cycles)]
  end

  # Each test runs in a child forked from a machine booted once per SID
  # model (see ForkedBoot). The deadline only catches a child stuck
  # outside its emulated cycles: at a hundred thousand cycles a second,
  # far slower than any machine this runs on, the budget alone would take
  # that long.
  def score(name, sid_model, timeout)
    deadline = 60 + ((timeout + BOOT_ALLOWANCE) / 100_000)
    booted(sid_model).run(deadline) { |computer| exit_code(computer, File.join(ROOT, name), timeout) }
  end

  def booted(sid_model)
    @booted ||= {}
    @booted[sid_model] ||= ForkedBoot.new(%w[TERM INT]) { ForkedBoot.computer(sid_model:) }
  end

  # Filters are name substrings, matched as a union; no filter runs
  # everything.
  def selected(filters, tests = self.tests)
    return tests if filters.empty?

    tests.select { |name, _| filters.any? { |filter| name.include?(filter) } }
  end

  def unmatched(filters, tests = self.tests)
    filters.reject { |filter| tests.keys.any? { |name| name.include?(filter) } }
  end

  def run(tests, results_path, sid_model = :mos6581)
    width = tests.keys.map(&:length).max
    results = tests.map do |name, timeout|
      result = score(name, sid_model, timeout)
      puts "#{name.ljust(width)} #{result}"
      $stdout.flush
      [name, result]
    end
    summarize(results, results_path)
  end

  def summarize(results, results_path)
    passed = results.count { |_, result| result == "PASS" }
    puts "#{passed}/#{results.length} passed"
    write_results(results_path, results) if results_path
    results.length - passed
  end

  def write_results(path, results)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, results.map { |name, result| record(name, result) }.join)
  end

  # bin/sidtests's command line, returning the exit status.
  def main(argv)
    list_only = argv.delete("--list")
    results_path = CLI.take_option(argv, "--results")
    sid_option = CLI.take_option(argv, "--sid") || "6581"
    sid_model = SID_MODELS.fetch(sid_option) do
      warn "sidtests: invalid argument: --sid #{sid_option}"
      return 2
    end

    tests = self.tests(sid_model)
    unmatched = unmatched(argv, tests)
    unless unmatched.empty?
      warn "No test matches #{unmatched.join(', ')}."
      return 2
    end

    tests = selected(argv, tests)

    if list_only
      tests.each_key { |name| puts name }
      return 0
    end

    run(tests, results_path, sid_model).zero? ? 0 : 1
  end
end
