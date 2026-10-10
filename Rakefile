# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

require_relative "test/support/suites"
require_relative "test/support/ci_matrix"
require_relative "test/support/z80_sample"
require_relative "spinel/check"
require_relative "native/build"
require_relative "native/pack"

VENDORED_REPOS = {
  "65x02" => {
    repo: "https://github.com/SingleStepTests/65x02",
    sparse: "6502/v1"
  },
  "z80" => {
    repo: "https://github.com/SingleStepTests/z80",
    sparse: "v1"
  },
  "VICE-testprogs" => {
    repo: "https://github.com/libsidplayfp/VICE-testprogs"
  }
}.freeze

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

# regression:<suite>-<n> for each stretch of a suite with :cuts.
def define_stretch_tasks
  Suites::ALL_SUITES.select { |_, config| config[:cuts] }.each do |suite, config|
    (1..(config[:cuts].length + 1)).each do |number|
      desc "Run stretch #{number} of the #{suite} chain and compare it against #{Suites.baseline_path(suite)}"
      task "#{suite}-#{number}" => "vendor:VICE-testprogs" do
        Suites.run_stretch(suite, number)
      end
    end
  end
end

def spinel_check(media)
  SpinelCheck.check_boot(*media)
  SpinelCheck.check_cpu_tests
  SpinelCheck.check_z80_tests
  SpinelCheck.check_vic20_boot
  SpinelCheck.check_vic20_boot("2000000", "1000000", "unexpanded", "44100")
  SpinelCheck.check_c128_boots
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

  desc "Fetch the first #{Z80Sample::CASES} cases of each SingleStepTests Z80 file into #{Z80Sample::DIR}"
  task "z80-sample" do
    Dir.exist?(Z80Sample::DIR) ? puts("z80-sample already present.") : Z80Sample.fetch
  end

  desc "Check out the vendored test repositories, with the Z80 sample in place of the whole Z80 suite"
  task checkout: VENDORED_REPOS.keys - ["z80"] + ["z80-sample"]
end

namespace :regression do
  Suites::ALL_SUITES.each_key do |suite|
    desc "Run #{suite} and compare the results against #{Suites::BASELINE_DIR}/#{suite}.txt"
    task suite => "vendor:VICE-testprogs" do
      results = File.join(Suites::REGRESSION_DIR, "#{suite}.txt")
      Suites.run_suite(suite, results)
      Suites.compare_baseline(suite, results)
    end
  end

  define_stretch_tasks

  namespace :record do
    Suites::ALL_SUITES.each_key do |suite|
      desc Suites.record_desc(suite)
      task suite, [:filter] => "vendor:VICE-testprogs" do |_task, args|
        filters = args.to_a.compact.reject(&:empty?)
        next Suites.record_chain(suite, *filters) if filters.any? && Suites.chain?(suite)
        next Suites.record_filtered(suite, filters) if filters.any?

        results = File.join(Suites::REGRESSION_DIR, "#{suite}-record.txt")
        Suites.run_suite(suite, results)
        cp(results, Suites.baseline_path(suite))
        puts "Recorded #{Suites.baseline_path(suite)}."
      end
    end
  end

  desc "Re-record every baseline in the main set"
  task record: Suites::REGRESSION_SUITES.keys.map { |suite| "regression:record:#{suite}" }
end

desc "Run every suite in the main set against its tracked baseline"
task regression: Suites::REGRESSION_SUITES.keys.map { |suite| "regression:#{suite}" }

namespace :spinel do
  desc "Compile the Spinel harnesses into #{SpinelCheck::OUT} (SPINEL=compiler, SPINEL_CC=C compiler)"
  task :build do
    Suites.spinel_build
  end

  desc "Check the Spinel build against CRuby: boot, or media for cycles, SingleStepTests, the VIC-20's and C128's boots"
  task :check, %i[media cycles] => %w[spinel:build vendor:65x02 vendor:z80-sample] do |_task, args|
    spinel_check(args[:media] ? [args[:cycles] || "23000000", "3000000", args[:media]] : [])
  end

  desc "Check the Spinel build's SID against CRuby's, sample for sample, on two csid-light tunes"
  task check_sid: "vendor:VICE-testprogs" do
    Suites.spinel_build(harnesses: %w[sid])
    SpinelCheck.check_sid
  end

  desc "Run the Lorenz chain on the Spinel build, its stretches side by side ([1,2] picks some, " \
       "[whole] runs it in one), and compare it against #{Suites::BASELINE_DIR}/lorenz.txt"
  task :lorenz, [:stretch] => "vendor:VICE-testprogs" do |_task, args|
    Suites.spinel_build(harnesses: %w[lorenz])
    recorded = Suites.read_recorded("lorenz")
    ranges = Suites.spinel_lorenz_ranges(recorded, args.to_a.compact.reject(&:empty?))
    results = SpinelCheck.run_lorenz(ranges.transform_values { |range| Suites.chain_args(range) })
    problems = ranges.filter_map do |name, range|
      Suites.stretch_problem("spinel-#{name}", range, recorded, results.fetch(name))
    end
    raise problems.join("\n") if problems.any?
  end
end

desc "Run the SID testprogs for a chip (6581 or 8580) on the Spinel build, over SHARDS processes (4), " \
     "and compare them against #{Suites::BASELINE_DIR}/sid.txt or sid-8580.txt"
task "spinel:sidtests", [:sid] => "vendor:VICE-testprogs" do |_task, args|
  Suites.spinel_sidtests(args[:sid] || "6581")
end

desc "Run the true-drive scenarios on the Spinel build and compare them against " \
     "#{Suites::BASELINE_DIR}/drive-scenarios.txt"
task "spinel:drive_scenarios" do
  Suites.spinel_build(harnesses: %w[drive_scenarios])
  results = File.join(SpinelCheck::OUT, "drive-scenarios.txt")
  Suites.run_suite("drive-scenarios", results, ["--engine", SpinelCheck.binary("drive_scenarios")])
  Suites.compare_baseline("drive-scenarios", results, name: "spinel-drive-scenarios")
end

desc "Run a bin/testbench suite (testbench unless named, or [all] of them) on the Spinel build, " \
     "or [suite,filter,...] of it, and compare it against its baseline in #{Suites::BASELINE_DIR}"
task "spinel:testbench", [:suite] => "vendor:VICE-testprogs" do |_task, args|
  suites = Suites.spinel_testbench_suites(args[:suite] || "testbench")
  filters = args.extras.compact.reject(&:empty?)
  raise "Filters take one suite, not all of them." if filters.any? && suites.length > 1

  harnesses = suites.map { |suite| Suites.spinel_testbench_engine(suite) }.uniq
  Suites.spinel_build(harnesses:)
  Suites.run_spinel_testbench(suites, filters)
end

namespace :ci do
  desc "Print the suites matrix for .github/workflows/ci.yml as JSON, derived from the suite table, " \
       "once it runs every suite and baseline row on exactly one shard"
  task :matrix do
    require "json"
    problems = CIMatrix.problems(CIMatrix.shard_tasks)
    raise problems.join("\n") if problems.any?

    puts JSON.pretty_generate("include" => CIMatrix.matrix)
  end
end

namespace :native do
  desc "Build the native badline into #{NativeBuild::BINARY} with Spinel " \
       "(SPINEL=compiler, SPINEL_CC=C compiler, SDL2_LDFLAGS=flags that find libSDL2)"
  task :build do
    NativeBuild.build(ENV.fetch("SPINEL", "spinel"), cc: ENV.fetch("SPINEL_CC", nil),
                                                     sdl2_flags: ENV.fetch("SDL2_LDFLAGS", nil))
  end

  desc "Pack the native badline with spin pack into #{NativeBuild::OUT}/badline-VERSION-spinel-COMMIT.tar.gz, " \
       "which builds with a C compiler and make alone (SPINEL=compiler, SPIN=spin, default: beside SPINEL)"
  task :pack do
    NativePack.pack(ENV.fetch("SPINEL", "spinel"), spin: ENV.fetch("SPIN", nil))
  end
end

desc "Build the native badline (native:build)"
task native: "native:build"

Rake::TestTask.new do |task|
  task.pattern = "test/test_*.rb"
end

Rake::Task["test"].enhance(["vendor:65x02", ENV["Z80_SAMPLE"] == "all" ? "vendor:z80" : "vendor:z80-sample"])
