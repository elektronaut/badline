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

  private

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
