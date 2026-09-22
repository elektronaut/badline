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
