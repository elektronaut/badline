# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

require_relative "test/regression"

VENDORED_REPOS = {
  "65x02" => {
    repo: "https://github.com/SingleStepTests/65x02",
    sparse: "6502/v1"
  },
  "VICE-testprogs" => {
    repo: "https://github.com/libsidplayfp/VICE-testprogs"
  }
}.freeze

# Headless suites whose per-test results are tracked as a baseline, mapped
# to the runner command that produces it. Each runner takes --results PATH
# and writes one tab-separated "id VERDICT [detail]" row per test; the guard
# compares those rows by id. bin/testbench takes id filters, so its
# testlist subtrees are separate suites with a baseline each.
REGRESSION_SUITES = {
  "testbench" => ["bin/testbench", "VICII/"],
  "lorenz" => ["bin/lorenz"],
  "sid" => ["bin/sidtests"]
}.freeze

# The rest of the testbench, split by the subsystem each subtree exercises.
# These get a rake task and a baseline but stay out of `rake regression`
# and the push-to-main CI set: CIA and interrupts alone are longer than the
# other three suites put together, mostly emulated runtime rather than
# timeouts, so they are run on demand instead.
OPT_IN_SUITES = {
  "testbench-cia" => ["bin/testbench", "CIA/"],
  "testbench-interrupts" => ["bin/testbench", "interrupts/"],
  "testbench-cpu" => ["bin/testbench", "CPU/"]
}.freeze

ALL_SUITES = REGRESSION_SUITES.merge(OPT_IN_SUITES).freeze
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
# expected to capture, so their status is ignored and the comparison decides.
def run_suite(suite, results)
  runner, *filters = ALL_SUITES.fetch(suite)
  mkdir_p(File.dirname(results))
  ruby("--yjit", runner, *filters, "--results", results) do |ok, _status|
    puts "#{runner} reported failing tests." unless ok
  end
  raise "#{runner} wrote no results to #{results}" unless File.exist?(results)
end

def compare_baseline(suite, results)
  baseline = baseline_path(suite)
  unless File.exist?(baseline)
    raise "No baseline at #{baseline}. Record one with " \
          "`rake regression:record:#{suite}`."
  end

  comparison = Regression::Comparison.new(
    suite, Regression.read(baseline), Regression.read(results)
  )
  comparison.report($stdout)
  comparison.publish
  raise "#{suite} changed against #{baseline}." if comparison.changed?
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
  ALL_SUITES.each_key do |suite|
    desc "Run #{suite} and compare the results against #{BASELINE_DIR}/#{suite}.txt"
    task suite => "vendor:VICE-testprogs" do
      results = File.join(REGRESSION_DIR, "#{suite}.txt")
      run_suite(suite, results)
      compare_baseline(suite, results)
    end
  end

  namespace :record do
    ALL_SUITES.each_key do |suite|
      desc "Re-record #{BASELINE_DIR}/#{suite}.txt from a fresh #{suite} run"
      task suite => "vendor:VICE-testprogs" do
        run_suite(suite, baseline_path(suite))
        puts "Recorded #{baseline_path(suite)}."
      end
    end
  end

  desc "Re-record every baseline in the push-to-main set"
  task record: REGRESSION_SUITES.keys.map { |suite| "regression:record:#{suite}" }
end

desc "Run every headless suite against its tracked baseline"
task regression: REGRESSION_SUITES.keys.map { |suite| "regression:#{suite}" }

Rake::TestTask.new do |task|
  task.pattern = "test/test_*.rb"
end

Rake::Task["test"].enhance(["vendor:65x02"])
