# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "regression"

class TestRegression < Minitest::Test
  BASELINE = <<~ROWS
    a\tPASS
    b\tFAIL\tdiff=12px
    c\tPASS
    dup\tPASS
    dup\tFAIL\tx
    gone\tPASS
  ROWS

  CURRENT = <<~ROWS
    a\tPASS
    fresh\tPASS
    b\tFAIL\tdiff=99px
    c\tFAIL\texit=$ff
    dup\tPASS
    dup\tFAIL\tx
    broken\tFAIL\ttimeout
  ROWS

  def setup
    @dir = Dir.mktmpdir
    @comparison = compare(BASELINE, CURRENT)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_changed_rows_are_keyed_by_id
    keys = @comparison.changed.map { |before, _| before.key }

    assert_equal %w[b c], keys
  end

  def test_changed_rows_carry_both_sides
    before, after = @comparison.changed.last

    assert_equal ["PASS", "FAIL exit=$ff"], [before.to_s, after.to_s]
  end

  def test_repeated_ids_are_keyed_by_occurrence
    assert_equal %w[a b c dup dup#2 gone], rows(BASELINE).keys
  end

  def test_added_rows_are_reported
    assert_equal %w[fresh broken], @comparison.added.map(&:key)
  end

  def test_removed_rows_are_reported
    assert_equal %w[gone], @comparison.removed.map(&:key)
  end

  def test_summary_counts_each_class
    assert_equal "demo: 2 changed, 2 new (1 pass, 1 fail), 1 gone", @comparison.summary
  end

  def test_a_changed_row_fails_the_run
    assert_predicate @comparison, :changed?
  end

  def test_upstream_growth_alone_does_not_fail_the_run
    comparison = compare("a\tPASS\ngone\tPASS\n", "a\tPASS\nfresh\tFAIL\texit=$ff\n")

    refute_predicate comparison, :changed?
  end

  def test_an_identical_run_reports_nothing
    assert_equal "demo: 0 changed, 0 new (0 pass, 0 fail), 0 gone",
                 compare(BASELINE, BASELINE).summary
  end

  def test_markdown_lists_every_class
    markdown = @comparison.markdown

    assert_includes markdown, "- `c`: `PASS` → `FAIL exit=$ff`"
  end

  def test_publish_appends_to_the_github_step_summary
    path = File.join(@dir, "summary.md")
    with_step_summary(path) { @comparison.publish }

    assert_includes File.read(path), @comparison.summary
  end

  def test_publish_is_a_no_op_without_a_step_summary
    with_step_summary(nil) { assert_nil @comparison.publish }
  end

  private

  def compare(baseline, current)
    Regression::Comparison.new("demo", rows(baseline), rows(current))
  end

  def rows(text)
    path = File.join(@dir, "rows-#{text.hash}.txt")
    File.write(path, text)
    Regression.read(path)
  end

  # CI sets GITHUB_STEP_SUMMARY, so both the set and the unset case have to
  # be arranged explicitly and the runner's own value put back.
  def with_step_summary(path)
    previous = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    replace_step_summary(path)
    yield
  ensure
    replace_step_summary(previous)
  end

  def replace_step_summary(path)
    if path
      ENV["GITHUB_STEP_SUMMARY"] = path
    else
      ENV.delete("GITHUB_STEP_SUMMARY")
    end
  end
end

class TestRegressionSplice < Minitest::Test
  BASELINE = <<~ROWS
    VICII/a/a1.prg	PASS
    VICII/a/a2.prg	FAIL	exit=$ff
    VICII/b/b1.prg	PASS
    VICII/c/c1.prg	FAIL	diff=4px
  ROWS

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_matched_row_takes_the_fresh_verdict
    splice = splice(BASELINE, "VICII/b/b1.prg\tFAIL\texit=$ff\n")

    assert_equal "FAIL exit=$ff", row(splice, "VICII/b/b1.prg").to_s
  end

  def test_untouched_rows_keep_their_verdict
    splice = splice(BASELINE, "VICII/b/b1.prg\tFAIL\texit=$ff\n")

    untouched = %w[VICII/a/a1.prg VICII/a/a2.prg VICII/c/c1.prg]
                .map { |key| row(splice, key).to_s }

    assert_equal ["PASS", "FAIL exit=$ff", "FAIL diff=4px"], untouched
  end

  def test_no_row_is_dropped
    splice = splice(BASELINE, "VICII/b/b1.prg\tPASS\n")

    assert_equal keys(BASELINE), splice.rows.map(&:key)
  end

  def test_baseline_order_is_preserved
    splice = splice(BASELINE, "VICII/c/c1.prg\tPASS\nVICII/a/a1.prg\tPASS\n")

    assert_equal keys(BASELINE), splice.rows.map(&:key)
  end

  def test_a_row_the_run_gained_is_inserted_beside_its_neighbour
    splice = splice(BASELINE, "VICII/a/a1.prg\tPASS\nVICII/a/a3.prg\tPASS\n")

    assert_equal ["VICII/a/a1.prg", "VICII/a/a3.prg", "VICII/a/a2.prg",
                  "VICII/b/b1.prg", "VICII/c/c1.prg"], splice.rows.map(&:key)
  end

  def test_a_gained_row_before_any_known_one_is_inserted_ahead_of_it
    splice = splice(BASELINE, "VICII/a/a0.prg\tPASS\nVICII/a/a1.prg\tPASS\n")

    assert_equal "VICII/a/a0.prg", splice.rows.first.key
  end

  def test_a_run_of_only_new_rows_lands_at_the_end
    splice = splice(BASELINE, "VICII/d/d1.prg\tPASS\n")

    assert_equal "VICII/d/d1.prg", splice.rows.last.key
  end

  def test_repeated_ids_survive_a_partial_record
    baseline = "x\tPASS\ndup\tPASS\ny\tPASS\ndup\tFAIL\told\n"
    splice = splice(baseline, "dup\tFAIL\tnew\ndup\tPASS\n")

    assert_equal ["PASS", "FAIL new", "PASS", "PASS"],
                 written(splice).values.map(&:to_s)
  end

  def test_a_repeated_id_is_not_renumbered_by_a_partial_record
    baseline = "x\tPASS\ndup\tPASS\ny\tPASS\ndup\tFAIL\told\n"
    splice = splice(baseline, "dup\tFAIL\tnew\ndup\tPASS\n")

    assert_equal %w[x dup y dup#2], written(splice).keys
  end

  def test_a_gained_occurrence_stays_next_to_the_one_it_follows
    baseline = "dup\tPASS\nz\tPASS\n"
    splice = splice(baseline, "dup\tPASS\ndup\tFAIL\tsecond\n")

    assert_equal %w[dup dup#2 z], written(splice).keys
  end

  def test_the_recorded_row_drops_the_occurrence_suffix
    assert_equal "dup\tFAIL\tx\n", rows("dup\tPASS\ndup\tFAIL\tx\n")["dup#2"].to_record
  end

  def test_summary_counts_what_moved
    splice = splice(BASELINE, "VICII/a/a1.prg\tPASS\nVICII/a/a3.prg\tPASS\n")

    assert_equal "1 row(s) re-recorded, 1 inserted, 3 left untouched", splice.summary
  end

  def test_write_round_trips_a_whole_baseline
    assert_equal rows(BASELINE), written(splice(BASELINE, "VICII/a/a1.prg\tPASS\n"))
  end

  CHAIN = <<~ROWS
    *\tPASS\tready. | start
    ldab\tPASS
    ldaz\tPASS
    ldazx\tPASS
    ldaa\tPASS
    aneb\tFAIL\t- load error!
    (suite)\tFAIL\thung after aneb
  ROWS

  def test_a_chain_range_resumes_one_test_ahead
    assert_equal "ldaz", chain_range("ldazx", "ldaa").resume_at
  end

  def test_a_chain_range_at_the_second_row_autostarts
    assert_nil chain_range("ldab").resume_at
  end

  def test_a_chain_range_at_the_first_row_autostarts
    assert_nil chain_range("*").resume_at
  end

  def test_a_chain_range_defaults_its_last_row_to_its_first
    assert_equal "ldaz", chain_range("ldaz").last
  end

  def test_a_chain_range_rejects_an_unknown_test
    error = assert_raises(ArgumentError) { chain_range("nope") }

    assert_match(/nope is not a row/, error.message)
  end

  def test_a_chain_range_rejects_an_unknown_last_test
    assert_raises(ArgumentError) { chain_range("ldab", "nope") }
  end

  def test_a_chain_range_rejects_the_outcome_row
    assert_raises(ArgumentError) { chain_range("(suite)") }
  end

  def test_a_chain_range_rejects_a_reversed_range
    assert_raises(ArgumentError) { chain_range("ldaa", "ldab") }
  end

  def test_a_chain_range_drops_the_resumed_segment
    fresh = "ldaz\tPASS\tready. | ldaz\nldazx\tPASS\nldaa\tPASS\n(suite)\tFAIL\tstopped after ldaa\n"

    assert_equal %w[ldazx ldaa], chain_range("ldazx", "ldaa").select(rows(fresh)).keys
  end

  def test_a_chain_range_drops_a_segment_past_its_last_row
    fresh = "ldaz\tPASS\nldazx\tPASS\nldaa\tFAIL\n"

    assert_equal %w[ldazx], chain_range("ldazx").select(rows(fresh)).keys
  end

  def test_a_chain_range_keeps_what_a_run_reached_short_of_its_last_row
    fresh = "ldaz\tPASS\nldazx\tFAIL\thung\n(suite)\tFAIL\thung after ldazx\n"

    assert_equal %w[ldazx], chain_range("ldazx", "ldaa").select(rows(fresh)).keys
  end

  def test_a_chain_range_reports_a_run_short_of_its_last_row
    range = chain_range("ldazx", "ldaa")

    refute range.reached?(range.select(rows("ldaz\tPASS\nldazx\tPASS\n")))
  end

  def test_a_chain_range_rejects_a_run_that_never_reached_it
    assert_raises(ArgumentError) { chain_range("ldaa").select(rows("ldaz\tPASS\n")) }
  end

  def test_a_chain_range_to_the_outcome_row_runs_to_the_end
    assert_predicate chain_range("aneb", "(suite)"), :to_end?
  end

  def test_a_chain_range_to_the_outcome_row_still_resumes_one_test_ahead
    assert_equal "ldaa", chain_range("aneb", "(suite)").resume_at
  end

  def test_a_chain_range_to_the_end_keeps_the_rows_the_baseline_lacks
    fresh = "ldaa\tPASS\naneb\tPASS\nlxab\tPASS\nfinish\tPASS\n(suite)\tPASS\tcompleted after finish\n"

    assert_equal %w[aneb lxab finish (suite)], chain_range("aneb", "(suite)").select(rows(fresh)).keys
  end

  def test_a_chain_range_to_the_end_is_reached_once_the_chain_ends
    range = chain_range("aneb", "(suite)")

    assert range.reached?(range.select(rows("aneb\tPASS\n(suite)\tFAIL\thung after aneb\n")))
  end

  def test_a_chain_splice_to_the_end_records_the_outcome_row
    fresh = chain_range("aneb", "(suite)")
            .select(rows("ldaa\tPASS\naneb\tPASS\nlxab\tPASS\n(suite)\tPASS\tcompleted\n"))

    assert_equal %w[* ldab ldaz ldazx ldaa aneb lxab (suite)],
                 written(Regression::Splice.new(rows(CHAIN), fresh)).keys
  end

  def test_a_chain_splice_leaves_the_outcome_row_alone
    fresh = chain_range("ldaz", "ldazx").select(
      rows("ldab\tPASS\tready.\nldaz\tFAIL\tnew\nldazx\tPASS\n(suite)\tFAIL\tstopped after ldazx\n")
    )

    assert_equal "FAIL hung after aneb", written(Regression::Splice.new(rows(CHAIN), fresh))["(suite)"].to_s
  end

  def test_a_chain_splice_replaces_only_the_range
    fresh = chain_range("ldaz").select(rows("ldab\tFAIL\tready.\nldaz\tFAIL\tnew\n"))
    expected = CHAIN.sub("ldaz\tPASS", "ldaz\tFAIL\tnew")

    assert_equal rows(expected), written(Regression::Splice.new(rows(CHAIN), fresh))
  end

  private

  def chain_range(first, last = nil)
    Regression::ChainRange.new(rows(CHAIN), first, last)
  end

  def splice(baseline, fresh)
    Regression::Splice.new(rows(baseline), rows(fresh))
  end

  def row(splice, key)
    splice.rows.find { |candidate| candidate.key == key }
  end

  def keys(text)
    rows(text).keys
  end

  # Re-reading what was written is what proves a splice cannot renumber the
  # occurrence suffixes, which only exist on the read side.
  def written(splice)
    path = File.join(@dir, "written.txt")
    Regression.write(path, splice.rows)
    Regression.read(path)
  end

  def rows(text)
    path = File.join(@dir, "rows-#{text.hash}.txt")
    File.write(path, text)
    Regression.read(path)
  end
end

load File.expand_path("../bin/lorenz", __dir__)

class TestLorenzSegments < Minitest::Test
  Capture = Struct.new(:output)
  Log = Data.define(:entries)
  Machine = Struct.new(:cpu)
  CPU = Class.new { def install_trap(*) = nil }

  TRANSCRIPT = "ldab - ok\nldaz - ok\nldazx"

  def test_a_stopped_run_drops_its_last_segment
    assert_equal %w[ldab ldaz], names("stopped")
  end

  def test_a_timed_out_run_drops_its_last_segment
    assert_equal %w[ldab ldaz], names("timeout")
  end

  def test_a_hung_run_keeps_its_last_segment
    assert_equal %w[ldab ldaz ldazx], names("hung")
  end

  def test_the_kept_segment_is_trimmed_of_the_next_name
    assert_equal "ldaz\tPASS", runner("stopped").segments.last.to_record
  end

  def test_the_chain_stops_once_it_loads_past_the_stop_test
    assert runner(nil, stop_after: "LDAZ").send(:moved_past_stop?)
  end

  def test_the_chain_runs_on_while_the_stop_test_is_the_last_loaded
    refute runner(nil, stop_after: "ldazx").send(:moved_past_stop?)
  end

  def test_a_finished_suite_counts_the_finish_row
    assert_equal "finish\tPASS\ttest suite 2.15+ completed",
                 Lorenz::Segment.new("finish", "finish\ntest suite 2.15+ completed - ok\n", halted: false).to_record
  end

  private

  def names(result)
    runner(result).segments.map(&:name)
  end

  def runner(result, stop_after: nil)
    entries = %w[ldab ldaz ldazx].map { |name| Lorenz::LoadLog::Entry.new(name, TRANSCRIPT.index(name)) }
    runner = Lorenz::Runner.new(Machine.new(CPU.new), Capture.new(TRANSCRIPT), Log.new(entries:),
                                stop_after:)
    runner.instance_variable_set(:@result, result)
    runner
  end
end

class TestLorenzDiskSwap < Minitest::Test
  Capture = Struct.new(:output)
  Disk = Struct.new(:files) do
    def read_file(name) = files[name]
    def label = files.keys.first
  end

  def setup
    @log = Lorenz::LoadLog.new(Disk.new({ "cia2tb" => [1] }), Capture.new(+""),
                               spares: [["Disk4.d64", Disk.new({ "aneb" => [2], "lxab" => [3] })]])
  end

  def test_a_program_on_the_mounted_image_loads_from_it
    assert_equal [1], load_program("cia2tb")
  end

  def test_a_program_only_on_the_spare_loads_from_it
    assert_equal [2], load_program("aneb")
  end

  def test_the_spare_stays_mounted_once_swapped_in
    load_program("aneb")

    assert_equal "aneb", @log.label
  end

  def test_a_program_on_no_disk_stays_missing
    assert_nil load_program("nope")
  end

  def test_the_load_is_logged_once
    load_program("aneb")

    assert_equal %w[aneb], @log.entries.map(&:name)
  end

  def test_there_is_no_spare_beside_an_image_without_one
    Dir.mktmpdir { |dir| assert_empty Lorenz.spares(File.join(dir, "Lorenz.d81")) }
  end

  def test_the_spare_is_not_the_mounted_image_itself
    Dir.mktmpdir do |dir|
      image = File.join(dir, Lorenz::NEXT_DISK)
      File.write(image, "")

      assert_empty Lorenz.spares(image)
    end
  end

  private

  def load_program(name)
    data = nil
    capture_io { data = @log.read_file(name) }
    data
  end
end
