# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "support/suites_status"

# Answers GET paths from a table and records every write.
class FakeGitHub
  attr_reader :repo, :writes

  def initialize(responses = {})
    @repo = "o/r"
    @responses = responses
    @writes = []
  end

  def get(path) = @responses.fetch(path)

  def get_all(path, key = nil)
    response = @responses.fetch(path)
    key ? response.fetch(key) : response
  end

  def post(path, body) = @writes << [:post, path, body]

  def patch(path, body) = @writes << [:patch, path, body]
end

class TestSuitesStatus < Minitest::Test
  JOBS = [
    { "name" => "Check what to run", "conclusion" => "success" },
    { "name" => "Suites / Harnesses", "conclusion" => "success" },
    { "name" => "Suites / Suites (cia)", "conclusion" => "failure" },
    { "name" => "Suites / Suites (c128)", "conclusion" => "failure" },
    { "name" => "Suites / Suites (drive)", "conclusion" => "success" },
    { "name" => "Report", "conclusion" => nil }
  ].freeze

  def setup
    @dir = Dir.mktmpdir
    write_moved("cia", name: "spinel-testbench-cia", key: "CIA/a.prg", before: "PASS", after: "FAIL exit=$ff")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_shard_is_read_from_its_job_name
    assert_equal "cia", SuitesStatus.shard("Suites / Suites (cia)")
  end

  def test_a_job_outside_the_matrix_has_no_shard
    assert_nil SuitesStatus.shard("Suites / Harnesses")
  end

  def test_a_moved_row_names_its_suite
    names = %w[spinel-testbench-cia sid spinel-lorenz-1 spinel-drive-scenarios spinel-testbench-c128]

    assert_equal(%w[testbench-cia sid lorenz drive-scenarios testbench-c128], names.map { |name| moved(name).suite })
  end

  def test_a_failed_shard_makes_the_run_red
    assert_equal "failure", verdict.state
  end

  def test_a_cancelled_run_is_an_error
    jobs = [{ "name" => "Suites / Suites (cia)", "conclusion" => "cancelled" }]

    assert_equal "error", verdict(jobs).state
  end

  def test_a_run_with_no_failures_is_green
    assert_equal "success", verdict(JOBS.reject { |job| job["conclusion"] == "failure" }).state
  end

  def test_the_moved_rows_are_read_per_shard
    assert_equal([%w[cia CIA/a.prg]], verdict.moved.map { |row| [row.shard, row.key] })
  end

  def test_a_failed_shard_without_moved_rows_is_unexplained
    assert_equal ["Suites / Suites (c128)"], verdict.unexplained
  end

  def test_blame_covers_moved_suites_and_unexplained_shards
    assert_equal %w[testbench-c128 testbench-cia], verdict.blamed
  end

  def test_a_failed_harness_build_blames_every_suite
    jobs = [{ "name" => "Suites / Harnesses", "conclusion" => "failure" }]

    assert_equal CIReach::ALL, verdict(jobs).blamed
  end

  def test_a_pull_reaching_a_blamed_suite_is_named
    assert pull(%w[testbench-cia spinel:check]).reaches?(%w[testbench-cia])
  end

  def test_a_pull_reaching_other_suites_is_not
    refute pull(%w[sid]).reaches?(%w[testbench-cia])
  end

  def test_a_pull_reaching_every_suite_is_named
    assert pull(CIReach::ALL).reaches?(%w[testbench-cia])
  end

  def test_a_pull_reaching_nothing_is_not_named_for_a_build_failure
    refute pull([]).reaches?(CIReach::ALL)
  end

  def test_a_scheduled_tick_skips_a_commit_with_a_status
    github = FakeGitHub.new(statuses("abc" => "pending"))

    refute SuitesStatus.start?(github, "abc", "schedule")
  end

  def test_a_scheduled_tick_runs_a_commit_without_one
    github = FakeGitHub.new("repos/o/r/commits/abc/statuses?per_page=100" => [{ "context" => "CI" }])

    assert SuitesStatus.start?(github, "abc", "schedule")
  end

  def test_a_dispatched_run_always_runs
    assert SuitesStatus.start?(FakeGitHub.new(statuses("abc" => "success")), "abc", "workflow_dispatch")
  end

  def test_the_last_green_commit_skips_red_and_unrun_ones
    github = FakeGitHub.new(statuses("c" => "failure", "a" => "success").merge(
                              "repos/o/r/commits/b/statuses?per_page=100" => []
                            ))

    assert_equal "a", SuitesStatus.last_green(github, %w[c b a])
  end

  def test_pulls_carry_the_suites_their_files_reach
    assert_equal([[7, %w[sid sid-8580 spinel:check spinel:check_sid testbench-cbm2 testbench-cbm5x0]]],
                 SuitesStatus.pulls(pull_github, %w[m]).map { |each| [each.number, each.reach] })
  end

  def test_a_red_run_opens_a_labelled_issue
    github = FakeGitHub.new(issues([]).merge("repos/o/r/labels?per_page=100" => [{ "name" => "suites-red" }]))
    SuitesStatus.open_or_update(github, body)

    method, path, payload = github.writes.last

    assert_equal [:post, "repos/o/r/issues", ["suites-red"]], [method, path, payload[:labels]]
  end

  def test_the_label_is_created_when_missing
    github = FakeGitHub.new(issues([]).merge("repos/o/r/labels?per_page=100" => []))
    SuitesStatus.open_or_update(github, body)

    assert_equal "repos/o/r/labels", github.writes.first[1]
  end

  def test_a_red_run_updates_the_open_issue
    github = FakeGitHub.new(issues([{ "number" => 9 }]))
    SuitesStatus.open_or_update(github, body)

    assert_equal([[:patch, "repos/o/r/issues/9"]], github.writes.map { |method, path, _| [method, path] })
  end

  def test_pull_requests_are_not_taken_for_the_issue
    github = FakeGitHub.new(issues([{ "number" => 3, "pull_request" => {} }]))

    assert_empty SuitesStatus.open_issues(github)
  end

  def test_a_green_run_closes_the_issue
    github = FakeGitHub.new(issues([{ "number" => 9 }]))
    SuitesStatus.close_issues(github, "abc", "url")

    assert_equal({ state: "closed", state_reason: "completed" }, github.writes.last[2])
  end

  def test_the_body_lists_the_moved_rows
    assert_includes body.to_s, "- `CIA/a.prg`: `PASS` → `FAIL exit=$ff`"
  end

  def test_the_body_names_unexplained_failures
    assert_includes body.to_s, "- Suites / Suites (c128)"
  end

  def test_the_body_links_the_range
    assert_includes body.to_s,
                    "[11111111...abcdef01](https://github.com/o/r/compare/1111111111...abcdef0123), 2 commit(s)"
  end

  def test_the_body_names_only_the_pulls_that_reach_the_blame
    text = body.to_s

    assert_equal [true, false], [text.include?("#1 CIA timers"), text.include?("#2 SID filter")]
  end

  def test_the_body_says_when_no_green_run_was_found
    assert_includes body(green: nil).to_s, "No green run in the last 100 commits on main."
  end

  private

  def write_moved(shard, **row)
    dir = File.join(@dir, "moved-#{shard}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "moved.jsonl"), "#{JSON.generate(row)}\n", mode: "a")
  end

  def moved(name) = SuitesStatus::Moved.new(shard: "s", name:, key: "k", before: "PASS", after: "FAIL")

  def verdict(jobs = JOBS) = SuitesStatus::Verdict.new(jobs, @dir)

  def pull(reach, number: 1, title: "t") = SuitesStatus::Pull.new(number:, title:, reach:)

  def statuses(states)
    states.to_h do |sha, state|
      ["repos/o/r/commits/#{sha}/statuses?per_page=100", [{ "context" => "suites", "state" => state }]]
    end
  end

  def issues(list) = { "repos/o/r/issues?labels=suites-red&state=open&per_page=100" => list }

  def pull_github
    FakeGitHub.new(
      "repos/o/r/commits/m/pulls" => [{ "number" => 7, "title" => "SID", "merged_at" => "2026-10-11" },
                                      { "number" => 8, "title" => "open", "merged_at" => nil }],
      "repos/o/r/pulls/7/files?per_page=100" => [{ "filename" => "lib/badline/chips/sid/voice.rb",
                                                   "previous_filename" => "spec/old_spec.rb" }]
    )
  end

  def body(green: "1111111111")
    pulls = [pull(%w[testbench-cia], number: 1, title: "CIA timers"), pull(%w[sid], number: 2, title: "SID filter")]
    red = SuitesStatus::Red.new(sha: "abcdef0123", run_url: "run", green:, commits: %w[abcdef0123 2222222222], pulls:,
                                compare_url: "https://github.com/o/r/compare/1111111111...abcdef0123")
    SuitesStatus::IssueBody.new(verdict, red)
  end
end
