# frozen_string_literal: true

require "rake"
require_relative "regression"
require_relative "../../spinel/check"
require_relative "../../spinel/sidtests_check"

# The headless suites with a tracked baseline, and running, comparing and
# re-recording them, for the Rakefile's regression and spinel tasks.
module Suites
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
  # :cuts splits a chain into stretches, regression:<suite>-1, -2 and so on,
  # that can run side by side, and spinel:lorenz runs them on Spinel the
  # same way. Each ends at its cut, and
  # the next resumes there on a fresh machine. Lorenz's cuts fall at quarters of its
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
  # These get a rake task and a baseline but stay out of `rake regression`:
  # their runtime is mostly emulated cycles rather than timeouts, so they
  # are run by name instead.
  # interrupts/irqdma is a suite of its own rather than part of interrupts —
  # 16 programs measuring DMA against interrupts over ~450M cycles each,
  # which is nearly all of that subtree's runtime and leaves the remaining
  # 13 rows at about a minute.
  # testbench-carts is the testlist's mountcrt rows, from whichever subtree
  # lists them, for the cartridge types badline has a mapper for.
  # testbench-cia-new is the testlist's cia-new rows, from whichever subtree
  # lists them, on a machine with 6526A CIAs. It is a suite of its own rather
  # than rows added to testbench-cia and the rest, because those baselines
  # are the 6526's, and many of its programs are listed for both chips under
  # the same id.
  # testbench-vicii-new is the testlist's vicii-new rows on a machine with an
  # 8565 VIC-II, kept apart from testbench for the same reason.
  # testbench-general is the machine-level rows of the testlist's C64/ and
  # general/ subtrees that the Lorenz suite leaves over: the power-on RAM
  # pattern, BASIC's pointers after a load, banking, the RAM under the CPU
  # port and emu-fuxxor's checks.
  # testbench-expansions is the testlist's rows that ask for a memory
  # expansion badline emulates, from whichever subtree lists them: the
  # geo512k rows on a machine with a 512K GEO-RAM, the plus60k and plus256k
  # rows on a machine with that RAM expansion fitted, and the REU rows on a
  # machine with an REU of the size each asks for. REU/floatingbus/floating3b
  # is left out: it never reports, and would spend most of the suite's time
  # running out its 1.5 billion cycles.
  # testbench-drive is the testlist's drive/ rows, and the included subtrees'
  # mountd64 ones, on a machine with a true 1541, which needs the DOS ROM.
  # drive/1541-testsuite, about twelve hours a row, is left out of it.
  # testbench-ntsc is the testlist's vicii-ntsc and vicii-ntscold rows, from
  # whichever subtree lists them, each on an NTSC machine with the VIC-II it
  # asks for, the 6567R8 or the 6567R56A. testbench-ntsc-vicii-new and
  # testbench-ntsc-cia-new are its rows that ask for the 8562 or for 6526A
  # CIAs, kept apart as testbench-vicii-new and testbench-cia-new are.
  # testbench-drean is the testlist's vicii-drean rows on a Drean C64, PAL-N
  # with the 6572, the one the testlist comments out included.
  # testbench-vic20 is the VIC-20 testlist's exitcode rows on a PAL VIC-20
  # with the RAM each asks for. Its Spinel build is spinel/vic20_testbench.rb,
  # which :engine names, so the C64's harness doesn't carry the VIC-20.
  # testbench-c128c64 is a curated part of the x128c64 testlist, the rows
  # where a C128 in C64 mode can differ from a C64C, on the C128 model each
  # asks for (Testbench::C128C64_DIRS has the rule). Its Spinel build is
  # spinel/c128_testbench.rb, so the C64's harness doesn't carry the C128.
  # testbench-c128 is the x128 testlist's rows that need C128 mode alone, on
  # a C128 that powers on in C128 mode (Testbench::C128_DIRS has the rule),
  # on the same Spinel build.
  # testbench-c128-z80 is the x128 testlist's rows that need the Z80
  # (bin/testbench --c128-z80), on the same machine and build: the per-opcode
  # timing in 1 MHz cycles, the OUTI and page relocation checks, and the Z80
  # side of c64modemmu. testbench-c128-zex is its zex128 rows, ZEXDOC and
  # ZEXALL, which run for 50 billion cycles in all, so CI leaves them out.
  # sid-8580 is bin/sidtests on the 8580 over the testlist's sid-new and
  # untagged programs; :args go to the runner as they are.
  # drive-scenarios is bin/drive_scenarios: the C64 and a true 1541 running
  # the DOS ROM through a save, a format, the error channel, the idle loop, a
  # write-protected disk and an autostart, a row per check, and CP/M 3.0
  # booting on a C128 from a true 1581. Its filters are scenario names.
  # drive-scenarios-cpm is ZEXDOC and ZEXALL run under that CP/M, which
  # bin/drive_scenarios runs only when named, for their billions of cycles.
  OPT_IN_SUITES = {
    "testbench-cia" => { runner: "bin/testbench", scope: "CIA/" },
    "testbench-interrupts" => { runner: "bin/testbench", scope: "interrupts/",
                                exclude: "interrupts/irqdma/" },
    "testbench-irqdma" => { runner: "bin/testbench", scope: "interrupts/irqdma/" },
    "testbench-cpu" => { runner: "bin/testbench", scope: "CPU/" },
    "testbench-carts" => { runner: "bin/testbench", args: %w[--carts] },
    "testbench-cia-new" => { runner: "bin/testbench", args: %w[--cia-new] },
    "testbench-vicii-new" => { runner: "bin/testbench", args: %w[--vicii-new] },
    "testbench-general" => { runner: "bin/testbench", scope: "C64/,general/" },
    "testbench-expansions" => { runner: "bin/testbench", args: %w[--expansions],
                                exclude: "REU/floatingbus/floating3b" },
    "testbench-drive" => { runner: "bin/testbench", args: %w[--drive] },
    "testbench-ntsc" => { runner: "bin/testbench", args: %w[--ntsc] },
    "testbench-ntsc-vicii-new" => { runner: "bin/testbench", args: %w[--ntsc --vicii-new] },
    "testbench-ntsc-cia-new" => { runner: "bin/testbench", args: %w[--ntsc --cia-new] },
    "testbench-drean" => { runner: "bin/testbench", args: %w[--drean] },
    "testbench-vic20" => { runner: "bin/testbench", args: %w[--vic20], engine: "vic20_testbench" },
    "testbench-c128c64" => { runner: "bin/testbench", args: %w[--c128c64], engine: "c128_testbench" },
    "testbench-c128" => { runner: "bin/testbench", args: %w[--c128], engine: "c128_testbench" },
    "testbench-c128-z80" => { runner: "bin/testbench", args: %w[--c128-z80], exclude: "c128/z80/zex128/",
                              engine: "c128_testbench" },
    "testbench-c128-zex" => { runner: "bin/testbench", args: %w[--c128-z80], scope: "c128/z80/zex128/",
                              engine: "c128_testbench" },
    "sid-8580" => { runner: "bin/sidtests", args: %w[--sid 8580] },
    "drive-scenarios" => { runner: "bin/drive_scenarios" },
    "drive-scenarios-cpm" => { runner: "bin/drive_scenarios", args: %w[cpm-zex] }
  }.freeze

  ALL_SUITES = REGRESSION_SUITES.merge(OPT_IN_SUITES).freeze
  BASELINE_DIR = "test/baselines"
  REGRESSION_DIR = "tmp/regression"

  # The bin/testbench suites on the Spinel build: bin/testbench runs each
  # one's tests on tmp/spinel/testbench, or the harness the suite's :engine
  # names, one build process per shard, and scores them as it does in
  # process.
  SPINEL_TESTBENCH_SUITES = ALL_SUITES.select { |_, config| config[:runner] == "bin/testbench" }.keys.freeze

  # Where each suite's baseline is, and reading, splicing and comparing
  # against it.
  module Baselines
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

    # With filters, only the baseline rows they match are expected, as
    # bin/testbench matches them (see Regression::Filters).
    def compare_baseline(suite, results, name: suite, filters: [])
      baseline = baseline_path(suite)
      unless File.exist?(baseline)
        raise "No baseline at #{baseline}. Record one with " \
              "`rake regression:record:#{suite}`."
      end

      expected = Regression.read(baseline)
      if filters.any?
        matcher = Regression::Filters.parse(filters)
        expected = expected.select { |_, row| matcher.selects?(row.id) }
      end
      comparison = Regression::Comparison.new(name, expected, Regression.read(results))
      comparison.report($stdout)
      comparison.publish
      raise "#{name} changed against #{baseline}." if comparison.changed?
    end
  end

  # Running a suite's runner, and passing signals on to it.
  module Runs
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
  end

  # Re-recording part of a baseline, and the stretches of a chained suite.
  module Records
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
    # are spliced in. The outcome row is left as the last whole run recorded it,
    # unless last is the outcome row itself: then the run goes on to the end of
    # the chain and records how it ended.
    def record_chain(suite, first, last = nil, *extra)
      raise "#{suite} takes a [first,last] stretch of the chain, not a filter list." if extra.any?

      recorded = read_recorded(suite)
      range = Regression::ChainRange.new(recorded, first, last)
      results = File.join(REGRESSION_DIR, "#{suite}-record.txt")
      run_suite(suite, results, chain_args(range))
      fresh = range.select(Regression.read(results))
      unless range.reached?(fresh)
        warn "WARNING: #{suite} ended before reaching #{range.last}. " \
             "Recording only the rows it reached."
      end
      splice_recorded(suite, recorded, fresh)
    end

    def chain_args(range)
      args = range.to_end? ? [] : ["--stop-after", range.last]
      args.push("--resume", range.resume_at) if range.resume_at
      args
    end

    # Runs stretch number (from 1) of a chained suite and compares its rows
    # against the baseline. Every stretch but the last stops after its cut, and
    # a stretch that ends short of that fails, since its missing rows would
    # otherwise only read as gone. The last runs the chain to its end, so it
    # also carries the (suite) row.
    def run_stretch(suite, number)
      recorded = read_recorded(suite)
      range = stretch_range(suite, recorded, number)
      results = File.join(REGRESSION_DIR, "#{suite}-#{number}.txt")
      run_suite(suite, results, chain_args(range))
      problem = stretch_problem("#{suite}-#{number}", range, recorded, results)
      raise problem if problem
    end

    # The range of stretch number, the last one running to the end of the chain.
    def stretch_range(suite, recorded, number)
      cuts = ALL_SUITES.fetch(suite).fetch(:cuts)
      keys = recorded.keys - [Regression::ChainRange::OUTCOME]
      first = number == 1 ? keys.first : keys[keys.index(cuts[number - 2]) + 1]
      last = number == cuts.length + 1 ? Regression::ChainRange::OUTCOME : cuts[number - 1]
      Regression::ChainRange.new(recorded, first, last)
    end

    # Compares a run of range against the baseline, returning what is wrong
    # with it, if anything.
    def stretch_problem(name, range, recorded, results)
      rows = range.select(Regression.read(results))
      expected = range.select(recorded)
      comparison = Regression::Comparison.new(name, expected, rows)
      comparison.report($stdout)
      comparison.publish
      return "#{name} changed against the baseline." if comparison.changed?
      return "#{name} ended before reaching #{range.last}." unless range.reached?(rows)
      return if rows.keys == expected.keys

      "#{name} reported #{rows.length} rows where the baseline has #{expected.length}."
    end

    # The Lorenz chain on the Spinel build: the stretches of `rake regression:lorenz-N`
    # numbered in picked, all of them when it is empty, or the whole chain in one
    # run when it is ["whole"].
    def spinel_lorenz_ranges(recorded, picked)
      if picked == ["whole"]
        first = (recorded.keys - [Regression::ChainRange::OUTCOME]).first
        return { "lorenz" => Regression::ChainRange.new(recorded, first, Regression::ChainRange::OUTCOME) }
      end

      numbers = (1..(ALL_SUITES.fetch("lorenz").fetch(:cuts).length + 1)).to_a
      unknown = picked - numbers.map(&:to_s)
      raise "No Lorenz stretch #{unknown.join(', ')}. Pick from #{numbers.join(', ')}, or whole." if unknown.any?

      numbers.select { |number| picked.empty? || picked.include?(number.to_s) }.to_h do |number|
        ["lorenz-#{number}", stretch_range("lorenz", recorded, number)]
      end
    end
  end

  # The suites on the Spinel build.
  module SpinelSuites
    def spinel_testbench_engine(suite) = ALL_SUITES.fetch(suite).fetch(:engine, "testbench")

    def spinel_testbench_suites(suite)
      return SPINEL_TESTBENCH_SUITES if suite == "all"
      raise "#{suite} is not a bin/testbench suite: #{SPINEL_TESTBENCH_SUITES.join(', ')}." unless
        SPINEL_TESTBENCH_SUITES.include?(suite)

      [suite]
    end

    # Runs each suite and compares it against its baseline, going on to the
    # next when one changed, and fails once they have all run. Filters bound a
    # single suite's run to the rows they match.
    def run_spinel_testbench(suites, filters = [])
      problems = suites.filter_map do |suite|
        results = File.join(SpinelCheck::OUT, "#{suite}.txt")
        run_suite(suite, results, [*filters, "--engine", SpinelCheck.binary(spinel_testbench_engine(suite))])
        compare_baseline(suite, results, name: "spinel-#{suite}", filters:)
        nil
      rescue RuntimeError => e
        e.message
      end
      raise problems.join("\n") if problems.any?
    end

    # The SID testprogs on the Spinel build, for the chip bin/sidtests --sid
    # takes, compared as regression:sid and regression:sid-8580 compare them.
    def spinel_sidtests(sid)
      suite = { "6581" => "sid", "8580" => "sid-8580" }.fetch(sid) { raise "No SID model #{sid}. Pick 6581 or 8580." }
      require_relative "sidtests"
      spinel_build(harnesses: %w[sidtests])
      tests = SIDTests.tests(SIDTests::SID_MODELS.fetch(sid))
      results = SpinelSIDTests.run("spinel-#{suite}", tests, sid, shards: Integer(ENV.fetch("SHARDS", "4")))
      compare_baseline(suite, results)
    end

    # Compiles the Spinel harnesses (SPINEL=compiler, SPINEL_CC=C compiler),
    # all of them unless harnesses names some.
    def spinel_build(**)
      SpinelCheck.build(ENV.fetch("SPINEL", "spinel"), cc: ENV.fetch("SPINEL_CC", nil), **)
    end
  end

  extend Rake::FileUtilsExt
  extend Baselines
  extend Runs
  extend Records
  extend SpinelSuites
end
