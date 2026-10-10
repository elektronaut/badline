# frozen_string_literal: true

require_relative "suites"

# The suites job matrix in .github/workflows/ci.yml, derived from the suite
# table, and the check that a matrix runs every suite and every baseline row
# on exactly one shard.
module CIMatrix
  # The shards, balanced by recent run times to about 10 minutes each. An
  # entry is a suite, or a suite and the filters its shard runs (the stretch
  # numbers for a chained suite), or one of CHECKS. testbench-irqdma is split
  # by filter: its b.prg rows, and the rest, nmitest6.prg among them because
  # it contains test6.prg. testbench-drive is split into its viavarious rows
  # and the rest, and lorenz by stretch.
  SHARDS = {
    "lorenz-1-2" => [%w[lorenz 1 2]],
    "lorenz-3-4" => [%w[lorenz 3 4]],
    "irqdma-1" => [%w[testbench-irqdma b.prg]],
    "irqdma-2" => [%w[testbench-irqdma test1.prg test2.prg test3.prg test4.prg test5.prg test6.prg test7.prg]],
    "cia" => %w[testbench-cia],
    "cia-new" => %w[testbench-cia-new],
    "expansions" => %w[testbench-expansions testbench-vicii-new testbench-general testbench-interrupts
                       testbench-ntsc-cia-new],
    "vicii-cpu" => %w[testbench testbench-cpu],
    "sid-ntsc" => %w[sid sid-8580 spinel:check spinel:check_sid testbench-ntsc testbench-ntsc-vicii-new
                     testbench-drean testbench-carts],
    "drive-via-1" => [%w[testbench-drive via1.prg via2.prg via3 via4.prg via5.prg via9.prg]],
    "drive-via-2" => [%w[testbench-drive via10 via11 via12 via13 via14 via20 via21]],
    "drive" => [%w[testbench-drive !viavarious], "drive-scenarios", "testbench-vic20"],
    "c128c64" => %w[testbench-c128c64],
    "c128" => %w[testbench-c128],
    "c128-z80-1" => [%w[testbench-c128-z80 c128z80timing/f c128z80timing/c c128z80timing/0 c128z80timing/1
                        c128z80timing/2 c128z80timing/3 c128z80timing/4]],
    "c128-z80-2" => [%w[testbench-c128-z80 !c128z80timing/f !c128z80timing/c !c128z80timing/0 !c128z80timing/1
                        !c128z80timing/2 !c128z80timing/3 !c128z80timing/4]]
  }.freeze

  # The tasks that check the Spinel build against CRuby rather than a
  # baseline, and the harnesses each needs.
  CHECKS = {
    "spinel:check" => %w[boot cpu_tests z80_tests vic20_boot c128_boot],
    "spinel:check_sid" => %w[sid]
  }.freeze

  # Suites CI leaves out, and why.
  EXCLUDED = {
    "testbench-c128-zex" => "ZEXDOC and ZEXALL run for 50 billion cycles",
    "drive-scenarios-cpm" => "ZEXDOC and ZEXALL under CP/M run for 60 billion cycles"
  }.freeze

  SID_MODELS = { "sid" => "6581", "sid-8580" => "8580" }.freeze

  # The matrix as ci.yml's include list types it, from SHARDS.
  module Derive
    def matrix
      SHARDS.map do |shard, entries|
        entries = entries.map { |entry| Array(entry) }
        { "shard" => shard,
          "harnesses" => entries.flat_map { |suite, *| harnesses(suite) }.uniq.join(" "),
          "tasks" => entries.map { |suite, *args| task(suite, args) }.join(" ") }
      end
    end

    def task(suite, args)
      return suite if CHECKS.key?(suite)

      case suite
      when "lorenz" then args.empty? ? "spinel:lorenz" : "spinel:lorenz[#{args.join(',')}]"
      when *SID_MODELS.keys then "spinel:sidtests[#{SID_MODELS.fetch(suite)}]"
      when "drive-scenarios" then "spinel:drive_scenarios"
      else "spinel:testbench[#{[suite, *args].join(',')}]"
      end
    end

    def harnesses(suite)
      return CHECKS[suite] if CHECKS.key?(suite)

      case suite
      when "lorenz" then %w[lorenz]
      when *SID_MODELS.keys then %w[sidtests]
      when "drive-scenarios" then %w[drive_scenarios]
      else [Suites.spinel_testbench_engine(suite)]
      end
    end

    # What regression.yml offers to dispatch: every suite and each stretch
    # of a chained one.
    def regression_choices
      Suites::ALL_SUITES.flat_map do |suite, config|
        stretches = config.fetch(:cuts, []).length
        [suite, *(stretches.zero? ? [] : (1..(stretches + 1)).map { |number| "#{suite}-#{number}" })]
      end
    end
  end

  # Which suites, and which of their rows or stretches, a matrix runs.
  module Coverage
    # The [suite, filters] pairs a rake task in the matrix runs, none for a
    # check.
    def runs(task)
      name, args = task.match(/\A([^\[]+)(?:\[(.*)\])?\z/).captures
      args = args.to_s.split(",")
      case name
      when *CHECKS.keys then []
      when "spinel:testbench" then testbench_runs(args)
      when "spinel:lorenz" then [["lorenz", args - ["whole"]]]
      when "spinel:sidtests" then [[SID_MODELS.key(args.first || "6581"), []]]
      when "spinel:drive_scenarios" then [["drive-scenarios", []]]
      else raise ArgumentError, "#{task} is not a suite task the matrix knows."
      end
    end

    def testbench_runs(args)
      suite, *filters = args
      return Suites::SPINEL_TESTBENCH_SUITES.map { |each| [each, []] } if suite == "all"

      [[suite || "testbench", filters]]
    end

    # The units a suite's runs are counted in, each a key mapped to what a
    # filter matches: a stretch number for a chained suite, otherwise a
    # baseline row and the id the runner's filters match against.
    def units(suite)
      config = Suites::ALL_SUITES.fetch(suite)
      return (1..(config.fetch(:cuts).length + 1)).to_h { |number| [number.to_s, number.to_s] } if config[:chain]

      Regression.read(Suites.baseline_path(suite)).to_h { |key, row| [key, row.id] }
    end

    def selects?(suite, filters, unit)
      return filters.empty? || filters.include?(unit) if Suites::ALL_SUITES.fetch(suite)[:chain]

      Regression::Filters.parse(filters).selects?(unit)
    end

    # Shard names mapped to the rake tasks each runs.
    def shard_tasks(include = matrix)
      include.to_h { |shard| [shard.fetch("shard"), shard.fetch("tasks").split] }
    end

    # Shard names mapped to the [suite, filters] pairs each runs.
    def shard_runs(tasks)
      tasks.transform_values { |list| list.flat_map { |task| runs(task) } }
    end

    # The suites CI should run that no shard does.
    def missing_suites(tasks)
      ran = shard_runs(tasks).values.flatten(1).map(&:first)
      Suites::ALL_SUITES.keys - EXCLUDED.keys - ran
    end

    # Each unit of a run suite that no shard runs, or more than one does.
    def unit_problems(tasks)
      by_suite = shard_runs(tasks).flat_map { |shard, runs| runs.map { |suite, filters| [suite, shard, filters] } }
                                  .group_by(&:first)
      by_suite.flat_map do |suite, runs|
        units(suite).filter_map do |key, unit|
          shards = runs.filter_map { |_, shard, filters| shard if selects?(suite, filters, unit) }
          unit_problem(suite, key, shards)
        end
      end
    end

    def unit_problem(suite, key, shards)
      return "#{suite}: no shard runs #{key}" if shards.empty?

      "#{suite}: #{key} runs on #{shards.join(', ')}" if shards.length > 1
    end

    def problems(tasks)
      missing_suites(tasks).map { |suite| "#{suite}: no shard runs it" } + unit_problems(tasks)
    end
  end

  extend Derive
  extend Coverage
end
