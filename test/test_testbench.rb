# frozen_string_literal: true

require "minitest/autorun"

TESTBENCH = File.expand_path("../bin/testbench", __dir__)
load TESTBENCH unless defined?(Testbench)

class TestTestbenchTestlist < Minitest::Test
  def parse(line)
    Testbench::Testlist.parse(line)
  end

  def test_parses_an_included_subtree
    test = parse("../CIA/irqdelay/,cia-irq-1.prg,exitcode,4000000,cia-old\n")

    assert_equal "CIA/irqdelay/cia-irq-1.prg", test.id
    assert_equal 4_000_000, test.timeout
  end

  def test_keeps_every_modelled_subsystem
    %w[VICII CIA interrupts CPU].each do |subtree|
      refute_nil parse("../#{subtree}/x/,t.prg,exitcode,1000")
    end
  end

  def test_drops_subtrees_for_unmodelled_hardware
    assert_nil parse("../REU/mirrors/,t.prg,exitcode,1000")
    assert_nil parse("../drive/rpm/,t.prg,exitcode,1000")
  end

  def test_drops_decimalmode_covered_by_singlesteptests
    assert_nil parse("../CPU/decimalmode/,cpu_decimal.prg,exitcode,1000")
  end

  def test_drops_types_the_runner_cannot_score
    assert_nil parse("../CIA/tod/,t.prg,analyzer,0")
    assert_nil parse("../CPU/cpuport/,t.prg,interactive,0")
  end

  def test_drops_options_the_emulator_does_not_model
    assert_nil parse("../CIA/tod/,t.prg,exitcode,1000,cia-new")
    assert_nil parse("../VICII/border/,t.prg,exitcode,1000,vicii-ntsc")
  end

  def test_keeps_the_cia_old_half_of_a_doubled_row
    refute_nil parse("../CIA/tod/,t.prg,exitcode,1000,cia-old")
  end

  def test_ignores_comments_and_blank_lines
    assert_nil parse("# ../CIA/tod/,t.prg,exitcode,1000")
    assert_nil parse("   \n")
  end
end

class TestTestbenchExpectations < Minitest::Test
  def test_case(*options)
    Testbench::TestCase.new("../CPU/cpujam", "t.prg", "exitcode", 1000, options)
  end

  def test_success_wants_a_zero_exit_code
    assert test_case.satisfied_by?(0x00)
  end

  def test_success_rejects_a_failure_code
    refute test_case.satisfied_by?(0xff)
  end

  def test_success_rejects_a_test_that_never_reported
    refute test_case.satisfied_by?(nil)
  end

  def test_error_wants_a_nonzero_exit_code
    assert test_case("expect:error").satisfied_by?(0xff)
  end

  def test_error_rejects_a_pass
    refute test_case("expect:error").satisfied_by?(0x00)
  end

  def test_error_rejects_a_test_that_never_reported
    refute test_case("expect:error").satisfied_by?(nil)
  end

  def test_timeout_wants_no_report_at_all
    assert test_case("expect:timeout").satisfied_by?(nil)
  end

  def test_timeout_rejects_a_reported_pass
    refute test_case("expect:timeout").satisfied_by?(0x00)
  end
end

class TestTestbenchSelection < Minitest::Test
  def tests(*ids)
    ids.map { |id| Testbench::TestCase.new("../#{File.dirname(id)}", File.basename(id), "exitcode", 1000, []) }
  end

  def selected(filters, **bounds)
    IDS.select { |id| Testbench::Testlist.selected?(tests(id).first, filters, bounds[:scope], bounds[:exclude]) }
  end

  IDS = ["VICII/border/t.prg", "interrupts/irqdma/test1.prg",
         "interrupts/irqnoack/test1.prg", "CPU/cpujam/t.prg"].freeze

  def test_no_filter_runs_the_whole_scope
    assert_equal ["interrupts/irqdma/test1.prg", "interrupts/irqnoack/test1.prg"],
                 selected([], scope: "interrupts/")
  end

  def test_a_filter_is_matched_inside_the_scope
    assert_equal ["interrupts/irqnoack/test1.prg"],
                 selected(["test1"], scope: "interrupts/irqnoack/")
  end

  def test_exclude_carves_a_subtree_out_of_the_scope
    assert_equal ["interrupts/irqnoack/test1.prg"],
                 selected([], scope: "interrupts/", exclude: "interrupts/irqdma/")
  end

  def test_filters_are_a_union
    assert_equal ["VICII/border/t.prg", "CPU/cpujam/t.prg"], selected(%w[border cpujam])
  end

  def test_a_filter_outside_the_scope_selects_nothing
    assert_empty selected(["cpujam"], scope: "VICII/")
  end

  def test_a_filter_that_matched_nothing_is_reported
    assert_equal ["nope"], Testbench::Testlist.unmatched(%w[border nope], tests(*IDS))
  end

  def test_a_filter_that_matched_is_not_reported
    assert_empty Testbench::Testlist.unmatched(["border"], tests(*IDS))
  end
end

class TestTestbenchSharding < Minitest::Test
  def groups(count, shards)
    tests = Array.new(count) do |index|
      Testbench::TestCase.new("../VICII/x", "t#{index}.prg", "exitcode", (index + 1) * 1000, [])
    end
    Testbench::Shards.split(tests, [shards, count].min)
  end

  def test_every_test_is_assigned_exactly_once
    indices = groups(20, 4).flatten(1).map(&:first)

    assert_equal (0...20).to_a, indices.sort
  end

  def test_shards_are_disjoint
    assert_equal 20, groups(20, 4).sum(&:length)
  end

  def test_each_shard_runs_its_tests_in_testlist_order
    groups(20, 4).each { |group| assert_equal group.map(&:first).sort, group.map(&:first) }
  end

  def test_the_longest_budgets_are_spread_across_shards
    heaviest = groups(20, 4).map { |group| group.map { |_, test| test.timeout }.max }

    assert_equal 4, heaviest.uniq.length
  end

  def test_more_shards_than_tests_collapses_to_one_per_test
    assert_equal 3, groups(3, 8).length
  end

  def test_merging_puts_the_records_back_in_testlist_order
    lines = ["3\tPASS", "0\tFAIL\texit=$ff", "12\tPASS"]

    assert_equal [[0, "FAIL\texit=$ff"], [3, "PASS"], [12, "PASS"]],
                 Testbench::Shards.merge(lines)
  end

  def test_a_record_round_trips_through_a_shard_file
    assert_equal [[7, "diff=4px exit=$00"]],
                 Testbench::Shards.merge([Testbench::Shards.record(7, "diff=4px exit=$00").chomp])
  end

  def test_shard_count_falls_back_to_the_default
    assert_equal [Testbench::Runner::DEFAULT_SHARDS, Etc.nprocessors].min,
                 with_env(nil) { Testbench::Runner.shard_count(nil) }
  end

  def test_shard_count_reads_the_environment
    assert_equal 2, with_env("2") { Testbench::Runner.shard_count(nil) }
  end

  def test_an_explicit_count_wins_over_the_environment
    assert_equal 1, with_env("8") { Testbench::Runner.shard_count("1") }
  end

  def test_shard_count_is_capped_by_the_cores_available
    assert_equal Etc.nprocessors, with_env(nil) { Testbench::Runner.shard_count("999") }
  end

  private

  def with_env(value)
    previous = ENV.fetch("SHARDS", nil)
    value ? ENV["SHARDS"] = value : ENV.delete("SHARDS")
    yield
  ensure
    previous ? ENV["SHARDS"] = previous : ENV.delete("SHARDS")
  end
end

class TestTestbenchInterruption < Minitest::Test
  # Each shard reports its PID down the pipe and then hangs in its first
  # test, standing in for a long run.
  class HangingRunner < Testbench::Runner
    def initialize(tests, results_path, pipe)
      super(tests, results_path, shards: 2)
      @pipe = pipe
    end

    private

    def run_one(_test)
      @pipe.puts(Process.pid)
      @pipe.flush
      sleep 60
      "PASS"
    end
  end

  def setup
    @results = File.join(Dir.mktmpdir("interrupt"), "results.txt")
    tests = Array.new(2) { |n| Testbench::TestCase.new("../VICII/x", "t#{n}.prg", "exitcode", 1000, []) }
    reader, writer = IO.pipe
    @runner = fork { run_runner(tests, writer) }
    writer.close
    @shards = Array.new(2) { Integer(reader.gets) }
    Process.kill("TERM", @runner)
    @status = wait_briefly(@runner)
  end

  def teardown
    [@runner, *@shards].each { |pid| Process.kill("KILL", pid) if alive?(pid) }
    Process.wait(@runner) unless @status
    FileUtils.rm_rf(File.dirname(@results))
  end

  def test_the_runner_reports_the_interruption
    assert_equal 3, @status&.exitstatus
  end

  def test_every_shard_is_stopped_with_the_runner
    assert_empty(@shards.select { |pid| alive?(pid) })
  end

  def test_an_interrupted_run_writes_no_results
    refute_path_exists @results
  end

  private

  def run_runner(tests, pipe)
    HangingRunner.new(tests, @results, pipe).run
    exit!(0)
  rescue Testbench::Interrupted
    exit!(3)
  end

  # A runner that waits out its shards instead of stopping them would
  # still exit once they finish, so it gets a few seconds and no more.
  def wait_briefly(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status

      sleep 0.05
    end
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
