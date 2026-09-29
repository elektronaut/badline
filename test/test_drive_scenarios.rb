# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

DRIVE_SCENARIOS = File.expand_path("../bin/drive_scenarios", __dir__)
load DRIVE_SCENARIOS unless defined?(DriveScenarios::Pool)
require "badline"

class TestDriveScenariosRunner < Minitest::Test
  def finish(output, name = "idle")
    out, = capture_io { @lines = DriveScenarios.finish(name, output, "pid 1 exit 1") }
    [@lines, out]
  end

  def test_selects_every_scenario_without_a_filter
    assert_equal DriveScenarios::CHECKS.keys, DriveScenarios.selected([])
  end

  def test_selects_scenarios_by_name_substring
    assert_equal %w[save read-only], DriveScenarios.selected(%w[sav read])
  end

  def test_names_a_filter_that_matches_nothing
    assert_equal %w[nope], DriveScenarios.unmatched(%w[idle nope])
  end

  def test_keeps_the_rows_a_scenario_reported_in_check_order
    lines, = finish("idle/matches-stepping\tPASS\nidle/sleeps\tPASS\n")

    assert_equal ["idle/sleeps\tPASS\n", "idle/matches-stepping\tPASS\n"], lines
  end

  def test_fails_each_check_a_crashed_scenario_left_unreported
    lines, = finish("idle/sleeps\tPASS\n")

    assert_equal "idle/matches-stepping\tFAIL\tcrashed: pid 1 exit 1\n", lines.last
  end

  def test_prints_the_rows_as_they_come
    _, out = finish("idle/sleeps\tPASS\nidle/matches-stepping\tPASS\n")

    assert_equal "idle/sleeps PASS\nidle/matches-stepping PASS\n", out
  end

  def test_writes_the_results_and_fails_on_a_failed_row
    Dir.mktmpdir do |dir|
      path = File.join(dir, "results.txt")
      status = nil
      capture_io { status = DriveScenarios.summarize(["a/b\tPASS\n", "a/c\tFAIL\tx\n"], path) }

      assert_equal [1, "a/b\tPASS\na/c\tFAIL\tx\n"], [status, File.read(path)]
    end
  end
end

class TestDriveScenarios < Minitest::Test
  def test_reports_a_passing_check
    report = DriveScenarios::Report.new("save")
    report.check("no-error", true, "printed an error")

    assert_equal "save/no-error\tPASS\n", report.rows
  end

  def test_reports_a_failing_check_with_its_detail
    report = DriveScenarios::Report.new("save")
    report.check("no-error", false, "printed an error")

    assert_equal "save/no-error\tFAIL\tprinted an error\n", report.rows
  end

  def test_finds_a_number_then_a_word_past_what_isnt_a_letter
    assert DriveScenarios::Runs.number_before?("RUN\n 0 OK\nREADY.", " 0", "OK")
  end

  def test_finds_no_word_after_another_number
    refute DriveScenarios::Runs.number_before?(" 73 OK\n", " 0", "OK")
  end

  def test_finds_no_word_past_a_letter
    refute DriveScenarios::Runs.number_before?(" 0 X OK\n", " 0", "OK")
  end

  def test_blank_disk_has_every_block_free_but_the_directorys
    Dir.mktmpdir do |dir|
      path = File.join(dir, "blank.d64")
      DriveScenarios::Images.blank_d64(path, "BLANK")

      assert_equal 664 + 19 - 2, DriveScenarios::Images.free_blocks(Badline::Storage::D64Image.new(path))
    end
  end

  def test_blank_disk_carries_its_name
    Dir.mktmpdir do |dir|
      path = File.join(dir, "blank.d64")
      DriveScenarios::Images.blank_d64(path, "SAVE TEST")

      assert_equal "SAVE TEST".bytes, Badline::Storage::D64Image.new(path).read_block(18, 0)[0x90, 9]
    end
  end

  def test_rejects_an_unknown_scenario
    assert_raises(ArgumentError) { DriveScenarios.run("nope", Dir.tmpdir) }
  end
end
