# frozen_string_literal: true

require "minitest/autorun"

SIDTESTS = File.expand_path("../bin/sidtests", __dir__)
load SIDTESTS unless defined?(SIDTests)

class TestSIDTestsTestlist < Minitest::Test
  def parse(line)
    SIDTests.parse(line)
  end

  def test_parses_an_8580_row
    assert_equal ["detect/detect-2-new.prg", 5_600_000],
                 parse("../SID/detect/,detect-2-new.prg,exitcode,5600000,sid-new\n")
  end

  def test_drops_6581_rows
    assert_nil parse("../SID/detect/,detect-2-old.prg,exitcode,5600000,sid-old")
  end

  def test_drops_rows_for_either_chip
    assert_nil parse("../SID/busvalue/,busvalue.prg,exitcode,5500000")
  end

  def test_drops_types_the_runner_cannot_score
    assert_nil parse("../SID/resid-test/,chipmodel.prg,analyzer,0,sid-new")
  end

  def test_drops_other_subtrees
    assert_nil parse("../CIA/tod/,t.prg,exitcode,1000,sid-new")
  end

  def test_ignores_comments_and_blank_lines
    assert_nil parse("#../SID/noisewriteback/,t.prg,exitcode,100000000,sid-new")
    assert_nil parse("   \n")
  end
end

class TestSIDTestsSelection < Minitest::Test
  TESTS = { "detect/detect-2-new.prg" => 1, "osc3-wave0/osc3-wave0-new.prg" => 2 }.freeze

  def test_keeps_the_6581_list_at_the_fixed_budget
    assert_equal [SIDTests::TIMEOUT], SIDTests.tests(:mos6581).values.uniq
  end

  def test_filters_by_name_substring
    assert_equal({ "detect/detect-2-new.prg" => 1 }, SIDTests.selected(["detect"], TESTS))
  end

  def test_reports_a_filter_that_matches_nothing
    assert_equal ["typo"], SIDTests.unmatched(%w[detect typo], TESTS)
  end
end
