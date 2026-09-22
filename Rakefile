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
# to the runner that produces it. Each runner takes --results PATH and
# writes one tab-separated "id VERDICT [detail]" row per test; the guard
# compares those rows by id. bin/testbench bounds a run to an id prefix
# with --scope, so its testlist subtrees are separate suites with a
# baseline each.
#
# Runners also take id filters, which is what a partial re-record runs.
# :chain marks a suite that chains itself from the first test loaded, like
# bin/lorenz, so it is cut down to a [first, last] stretch of the chain
# instead.
#
# :cuts splits a chain into stretches that CI runs side by side as
# regression:<suite>-1, -2 and so on, each ending at its cut and the next
# resuming there on a fresh machine. Lorenz's cuts fall at quarters of its
# runtime, inside the CPU instruction tests. Keep every cut before trap1
# (row 221 of lorenz.txt): from there on the trap, MMU, interrupt and CIA
# tests carry state from one test to the next, which a fresh machine would
# lose. A moved cut has to be checked by resuming there and comparing the
# rows after it against the baseline; each of these left them exactly as
# the whole chain records them.
REGRESSION_SUITES = {
  "testbench" => { runner: "bin/testbench", scope: "VICII/" },
  "lorenz" => { runner: "bin/lorenz", chain: true, cuts: %w[rola cmpix insay] },
  "sid" => { runner: "bin/sidtests" }
}.freeze

# The rest of the testbench, split by the subsystem each subtree exercises.
# These get a rake task and a baseline but stay out of `rake regression`
# and the nightly CI set: their runtime is mostly emulated cycles
# rather than timeouts, so they are run on demand instead.
# interrupts/irqdma is a suite of its own rather than part of interrupts —
# 16 programs measuring DMA against interrupts over ~450M cycles each,
# which is nearly all of that subtree's runtime and leaves the remaining
# 13 rows at about a minute.
# sid-8580 is bin/sidtests on the 8580 over the testlist's sid-new programs;
# :args go to the runner as they are.
OPT_IN_SUITES = {
  "testbench-cia" => { runner: "bin/testbench", scope: "CIA/" },
  "testbench-interrupts" => { runner: "bin/testbench", scope: "interrupts/",
                              exclude: "interrupts/irqdma/" },
  "testbench-irqdma" => { runner: "bin/testbench", scope: "interrupts/irqdma/" },
  "testbench-cpu" => { runner: "bin/testbench", scope: "CPU/" },
  "sid-8580" => { runner: "bin/sidtests", args: %w[--sid 8580] }
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

def chain?(suite)
  ALL_SUITES.fetch(suite).fetch(:chain, false)
end

def record_desc(suite)
  return "Re-record #{baseline_path(suite)}, whole or a [first,last] stretch of the chain" if chain?(suite)

  "Re-record #{baseline_path(suite)}, whole or [filter,...] of it"
end

# The runners exit non-zero while any test fails, which a baseline is
# expected to capture, so their status is ignored and the comparison
# decides. Status 2 is the exception: a filter that matched no test, which
# would otherwise look like a clean run of nothing.
def run_suite(suite, results, filters = [])
  config = ALL_SUITES.fetch(suite)
  runner = config.fetch(:runner)
  mkdir_p(File.dirname(results))
  rm_f(results)
  status = spawn_runner("--yjit", runner, *scope_args(config), *filters, *resume_args(config),
                        "--results", results)
  raise "#{runner} matched no test. Check the filter." if status.exitstatus == 2

  puts "#{runner} reported failing tests." unless status.success?
  raise "#{runner} wrote no results to #{results}" unless File.exist?(results)
end

# TERM or INT to rake is passed on to the runner, so stopping rake's PID
# stops the run instead of orphaning the runner. The runner is waited for
# before the task fails, so it has stopped by the time rake exits.
def spawn_runner(*args)
  pid = nil
  interrupted = nil
  previous = %w[TERM INT].to_h do |signal|
    [signal, trap(signal) do
      interrupted ||= signal
      forward_signal(signal, pid) if pid
    end]
  end
  puts [FileUtils::RUBY, *args].join(" ")
  pid = Process.spawn(FileUtils::RUBY, *args)
  forward_signal(interrupted, pid) if interrupted
  status = Process.wait2(pid).last
  raise "#{args[1]} interrupted by SIG#{interrupted}." if interrupted

  status
ensure
  previous&.each { |signal, handler| trap(signal, handler) }
end

def forward_signal(signal, pid)
  Process.kill(signal, pid)
rescue Errno::ESRCH
  nil
end

# RESUME=1 carries a killed run on from the rows it finished, which only
# bin/testbench keeps. Each task's results path is fixed, so the same task
# run again finds its own progress file.
def resume_args(config)
  return [] unless ENV["RESUME"] == "1"

  runner = config.fetch(:runner)
  raise "RESUME=1 needs a bin/testbench suite. #{runner} can't resume." unless runner == "bin/testbench"

  ["--resume"]
end

def scope_args(config)
  args = []
  args.push("--scope", config[:scope]) if config[:scope]
  args.push("--exclude", config[:exclude]) if config[:exclude]
  args.concat(config.fetch(:args, []))
end

# Re-records only the rows a filter matched, splicing them into the
# existing baseline so every other row keeps the verdict it had.
def record_filtered(suite, filters)
  recorded = read_recorded(suite)
  results = File.join(REGRESSION_DIR, "#{suite}-record.txt")
  run_suite(suite, results, filters)
  splice_recorded(suite, recorded, Regression.read(results))
end

# Re-records a stretch of a chained suite: the run resumes just ahead of
# first, stops once last's segment is whole, and only the rows in between
# are spliced in. The outcome row is left as the last whole run recorded it.
def record_chain(suite, first, last = nil, *extra)
  raise "#{suite} takes a [first,last] stretch of the chain, not a filter list." if extra.any?

  recorded = read_recorded(suite)
  range = Regression::ChainRange.new(recorded, first, last)
  args = ["--stop-after", range.last]
  args.push("--resume", range.resume_at) if range.resume_at
  results = File.join(REGRESSION_DIR, "#{suite}-record.txt")
  run_suite(suite, results, args)
  fresh = range.select(Regression.read(results))
  unless range.reached?(fresh)
    warn "WARNING: #{suite} ended before reaching #{range.last}. " \
         "Recording only the rows it reached."
  end
  splice_recorded(suite, recorded, fresh)
end

# Runs stretch number (from 1) of a chained suite and compares its rows
# against the baseline. Every stretch but the last stops after its cut, and
# a stretch that ends short of that fails, since its missing rows would
# otherwise only read as gone. The last runs the chain to its end, so it
# also carries the (suite) row.
def run_stretch(suite, number)
  recorded = read_recorded(suite)
  range, final = stretch_range(suite, recorded, number)
  args = final ? [] : ["--stop-after", range.last]
  args.push("--resume", range.resume_at) if range.resume_at
  results = File.join(REGRESSION_DIR, "#{suite}-#{number}.txt")
  run_suite(suite, results, args)
  fresh = Regression.read(results)
  rows = range.select(fresh)
  expected = recorded.slice(*stretch_keys(recorded, range))
  if final
    rows[Regression::ChainRange::OUTCOME] = fresh[Regression::ChainRange::OUTCOME]
    expected[Regression::ChainRange::OUTCOME] = recorded[Regression::ChainRange::OUTCOME]
  end
  compare_stretch("#{suite}-#{number}", expected, rows.compact)
  raise "#{suite}-#{number} ended before reaching #{range.last}." unless range.reached?(rows)
  return if rows.keys == expected.keys

  raise "#{suite}-#{number} reported #{rows.length} rows where the baseline has #{expected.length}."
end

# The range of stretch number, and whether it is the last.
def stretch_range(suite, recorded, number)
  cuts = ALL_SUITES.fetch(suite).fetch(:cuts)
  keys = recorded.keys - [Regression::ChainRange::OUTCOME]
  first = number == 1 ? keys.first : keys[keys.index(cuts[number - 2]) + 1]
  final = number == cuts.length + 1
  [Regression::ChainRange.new(recorded, first, final ? keys.last : cuts[number - 1]), final]
end

def stretch_keys(recorded, range)
  keys = recorded.keys - [Regression::ChainRange::OUTCOME]
  keys[keys.index(range.first)..keys.index(range.last)]
end

def compare_stretch(name, expected, rows)
  comparison = Regression::Comparison.new(name, expected, rows)
  comparison.report($stdout)
  comparison.publish
  raise "#{name} changed against the baseline." if comparison.changed?
end

# regression:<suite>-<n> for each stretch of a suite with :cuts.
def define_stretch_tasks
  ALL_SUITES.select { |_, config| config[:cuts] }.each do |suite, config|
    (1..(config[:cuts].length + 1)).each do |number|
      desc "Run stretch #{number} of the #{suite} chain and compare it against #{baseline_path(suite)}"
      task "#{suite}-#{number}" => "vendor:VICE-testprogs" do
        run_stretch(suite, number)
      end
    end
  end
end

def read_recorded(suite)
  baseline = baseline_path(suite)
  unless File.exist?(baseline)
    raise "No baseline at #{baseline}. Record the whole suite first with " \
          "`rake regression:record:#{suite}`."
  end

  Regression.read(baseline)
end

def splice_recorded(suite, recorded, fresh)
  baseline = baseline_path(suite)
  # Against the rows the run touched, so the untouched majority does not
  # read as gone.
  Regression::Comparison.new(suite, recorded.slice(*fresh.keys), fresh).report($stdout)
  splice = Regression::Splice.new(recorded, fresh)
  Regression.write(baseline, splice.rows)
  puts "Recorded #{baseline}: #{splice.summary}."
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

  define_stretch_tasks

  namespace :record do
    ALL_SUITES.each_key do |suite|
      desc record_desc(suite)
      task suite, [:filter] => "vendor:VICE-testprogs" do |_task, args|
        filters = args.to_a.compact.reject(&:empty?)
        next record_chain(suite, *filters) if filters.any? && chain?(suite)
        next record_filtered(suite, filters) if filters.any?

        results = File.join(REGRESSION_DIR, "#{suite}-record.txt")
        run_suite(suite, results)
        cp(results, baseline_path(suite))
        puts "Recorded #{baseline_path(suite)}."
      end
    end
  end

  desc "Re-record every baseline in the nightly set"
  task record: REGRESSION_SUITES.keys.map { |suite| "regression:record:#{suite}" }
end

desc "Run every headless suite against its tracked baseline"
task regression: REGRESSION_SUITES.keys.map { |suite| "regression:#{suite}" }

Rake::TestTask.new do |task|
  task.pattern = "test/test_*.rb"
end

Rake::Task["test"].enhance(["vendor:65x02"])
