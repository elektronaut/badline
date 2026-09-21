# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

VENDORED_REPOS = {
  "65x02" => {
    repo: "https://github.com/SingleStepTests/65x02",
    sparse: "6502/v1"
  },
  "VICE-testprogs" => {
    repo: "https://github.com/libsidplayfp/VICE-testprogs"
  }
}.freeze

# Headless suites whose full output is tracked as a baseline, mapped to the
# runner that produces it. Each runner takes --results PATH and writes one
# file; the guard is a plain diff against the recorded copy.
REGRESSION_SUITES = {
  "testbench" => "bin/testbench",
  "lorenz" => "bin/lorenz",
  "sid" => "bin/sidtests"
}.freeze
BASELINE_DIR = "test/baselines"
REGRESSION_DIR = "tmp/regression"

# Check out a vendored test repository with a single shallow, blobless
# partial clone, optionally restricted to a sparse subpath. Git only
# transfers the (compressed) blobs we ask for, so this is far cheaper than
# fetching each file over HTTP. The tests read straight out of the checkout.
def checkout_vendored(dir, repo:, sparse: nil)
  require "fileutils"

  args = ["git", "clone", "--quiet", "--depth", "1", "--filter=blob:none"]
  args << "--no-checkout" if sparse
  sh(*args, repo, dir)
  return unless sparse

  Dir.chdir(dir) do
    sh("git", "sparse-checkout", "set", sparse)
    sh("git", "checkout", "--quiet")
  end
rescue StandardError
  FileUtils.rm_rf(dir)
  raise
end

task default: "test"

def baseline_path(suite)
  File.join(BASELINE_DIR, "#{suite}.txt")
end

# The runners exit non-zero while any test fails, which a baseline is
# expected to capture, so their status is ignored and the diff decides.
def run_suite(suite, results)
  runner = REGRESSION_SUITES.fetch(suite)
  mkdir_p(File.dirname(results))
  ruby("--jit", runner, "--results", results) do |ok, _status|
    puts "#{runner} reported failing tests." unless ok
  end
  raise "#{runner} wrote no results to #{results}" unless File.exist?(results)
end

def diff_baseline(suite, results)
  baseline = baseline_path(suite)
  unless File.exist?(baseline)
    raise "No baseline at #{baseline}. Record one with " \
          "`rake regression:record:#{suite}`."
  end

  sh("diff", "-u", "-L", "baseline", "-L", "current", baseline, results) do |ok, _|
    raise "#{suite} differs from #{baseline}." unless ok

    puts "#{suite}: matches #{baseline}."
  end
end

namespace :vendor do
  VENDORED_REPOS.each do |name, config|
    desc "Check out #{name} into vendor/#{name} unless already present"
    task name do
      dir = File.join("vendor", name)
      if Dir.exist?(File.join(dir, config[:sparse].to_s))
        puts "#{name} already present."
      else
        puts "Checking out #{name} into #{dir} from #{config[:repo]}"
        checkout_vendored(dir, **config)
      end
    end
  end

  desc "Check out all vendored test repositories"
  task checkout: VENDORED_REPOS.keys
end

namespace :regression do
  REGRESSION_SUITES.each_key do |suite|
    desc "Run #{suite} and diff the results against #{BASELINE_DIR}/#{suite}.txt"
    task suite => "vendor:VICE-testprogs" do
      results = File.join(REGRESSION_DIR, "#{suite}.txt")
      run_suite(suite, results)
      diff_baseline(suite, results)
    end
  end

  namespace :record do
    REGRESSION_SUITES.each_key do |suite|
      desc "Re-record #{BASELINE_DIR}/#{suite}.txt from a fresh #{suite} run"
      task suite => "vendor:VICE-testprogs" do
        run_suite(suite, baseline_path(suite))
        puts "Recorded #{baseline_path(suite)}."
      end
    end
  end

  desc "Re-record every baseline"
  task record: REGRESSION_SUITES.keys.map { |suite| "regression:record:#{suite}" }
end

desc "Run every headless suite against its tracked baseline"
task regression: REGRESSION_SUITES.keys.map { |suite| "regression:#{suite}" }

Rake::TestTask.new do |task|
  task.pattern = "test/test_*.rb"
end

Rake::Task["test"].enhance(["vendor:65x02"])
