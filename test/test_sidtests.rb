# frozen_string_literal: true

require "minitest/autorun"

SIDTESTS = File.expand_path("../bin/sidtests", __dir__)
load SIDTESTS unless defined?(SIDTests)

class TestSIDTestsTestlist < Minitest::Test
  def parse(line, sid_model = :mos8580)
    SIDTests.parse(line, sid_model)
  end

  def test_parses_an_8580_row
    assert_equal ["detect/detect-2-new.prg", 5_600_000],
                 parse("../SID/detect/,detect-2-new.prg,exitcode,5600000,sid-new\n")
  end

  def test_drops_6581_rows_from_the_8580_list
    assert_nil parse("../SID/detect/,detect-2-old.prg,exitcode,5600000,sid-old")
  end

  def test_drops_rows_for_either_chip_from_the_8580_list
    assert_nil parse("../SID/busvalue/,busvalue.prg,exitcode,5500000")
  end

  def test_parses_a_6581_row
    assert_equal ["detect/detect-2-old.prg", 5_600_000],
                 parse("../SID/detect/,detect-2-old.prg,exitcode,5600000,sid-old", :mos6581)
  end

  def test_keeps_rows_for_either_chip_in_the_6581_list
    refute_nil parse("../SID/busvalue/,busvalue.prg,exitcode,5500000", :mos6581)
  end

  def test_drops_8580_rows_from_the_6581_list
    assert_nil parse("../SID/detect/,detect-2-new.prg,exitcode,5600000,sid-new", :mos6581)
  end

  def test_drops_rows_that_mount_a_disk
    assert_nil parse("../SID/resid-test/,boundary.prg,exitcode,80000000,mountd64:boundary.d64", :mos6581)
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

  def test_filters_by_name_substring
    assert_equal({ "detect/detect-2-new.prg" => 1 }, SIDTests.selected(["detect"], TESTS))
  end

  def test_reports_a_filter_that_matches_nothing
    assert_equal ["typo"], SIDTests.unmatched(%w[detect typo], TESTS)
  end
end
