# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/suites"

class TestSuites < Minitest::Test
  # A Lorenz baseline cut down to a row on either side of each cut.
  KEYS = %w[* ldab rola rolz cmpix cmpiy insay insaz (suite)].freeze

  def recorded
    KEYS.to_h { |key| [key, Regression::Row.new(key, "PASS", nil)] }
  end

  def stretch(number)
    range = Suites.stretch_range("lorenz", recorded, number)
    [range.first, range.last]
  end

  def test_the_first_stretch_runs_from_the_chain_start_to_the_first_cut
    assert_equal %w[* rola], stretch(1)
  end

  def test_a_middle_stretch_runs_from_after_one_cut_to_the_next
    assert_equal %w[rolz cmpix], stretch(2)
  end

  def test_the_last_stretch_runs_to_the_outcome_row
    assert_equal %w[insaz (suite)], stretch(4)
  end

  def test_a_stretch_stops_after_its_cut_and_resumes_one_test_ahead
    assert_equal %w[--stop-after cmpix --resume rola], Suites.chain_args(Suites.stretch_range("lorenz", recorded, 2))
  end

  def test_the_last_stretch_runs_to_the_end
    assert_equal %w[--resume insay], Suites.chain_args(Suites.stretch_range("lorenz", recorded, 4))
  end

  def test_the_spinel_lorenz_ranges_default_to_every_stretch
    assert_equal %w[lorenz-1 lorenz-2 lorenz-3 lorenz-4], Suites.spinel_lorenz_ranges(recorded, []).keys
  end

  def test_the_spinel_lorenz_ranges_pick_stretches
    assert_equal %w[lorenz-2 lorenz-4], Suites.spinel_lorenz_ranges(recorded, %w[4 2]).keys
  end

  def test_the_whole_spinel_lorenz_chain_is_one_range
    range = Suites.spinel_lorenz_ranges(recorded, %w[whole]).fetch("lorenz")

    assert_equal %w[* (suite)], [range.first, range.last]
  end

  def test_an_unknown_spinel_lorenz_stretch_is_refused
    assert_raises(RuntimeError) { Suites.spinel_lorenz_ranges(recorded, %w[5]) }
  end

  def test_a_scoped_suite_passes_its_scope_and_exclusion
    assert_equal %w[--scope interrupts/ --exclude interrupts/irqdma/],
                 Suites.scope_args(Suites::ALL_SUITES.fetch("testbench-interrupts"))
  end

  def test_a_suite_passes_its_arguments_as_they_are
    assert_equal %w[--sid 8580], Suites.scope_args(Suites::ALL_SUITES.fetch("sid-8580"))
  end

  def test_every_testbench_suite_runs_on_the_spinel_build
    assert_equal Suites::SPINEL_TESTBENCH_SUITES, Suites.spinel_testbench_suites("all")
  end

  def test_a_suite_another_runner_runs_is_not_a_spinel_testbench_suite
    assert_raises(RuntimeError) { Suites.spinel_testbench_suites("sid") }
  end
end
