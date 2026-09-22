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
