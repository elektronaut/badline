# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "support/ci_matrix"

class TestCIMatrix < Minitest::Test
  WORKFLOWS = File.expand_path("../.github/workflows", __dir__)

  def workflow(name)
    YAML.load_file(File.join(WORKFLOWS, name))
  end

  def test_the_matrix_runs_every_suite
    missing = CIMatrix.missing_suites(CIMatrix.shard_tasks)

    assert_empty missing, "No shard runs #{missing.join(', ')}"
  end

  def test_the_matrix_runs_every_baseline_row_on_one_shard
    problems = CIMatrix.unit_problems(CIMatrix.shard_tasks)

    assert_empty problems, "The shards don't run each row once:\n#{problems.join("\n")}"
  end

  def test_regression_yml_offers_every_suite_and_stretch
    inputs = workflow("regression.yml").fetch(true).dig("workflow_dispatch", "inputs", "suite", "options")
    expected = ["all", *CIMatrix.regression_choices]

    assert_empty expected - inputs, "regression.yml's choices lack #{(expected - inputs).join(', ')}"
  end

  def test_regression_yml_offers_no_unknown_suite
    inputs = workflow("regression.yml").fetch(true).dig("workflow_dispatch", "inputs", "suite", "options")
    unknown = inputs - ["all", *CIMatrix.regression_choices]

    assert_empty unknown, "regression.yml offers #{unknown.join(', ')}, which no suite or stretch is"
  end

  def test_a_row_no_filter_matches_is_named
    problems = CIMatrix.unit_problems("irqdma" => ["spinel:testbench[testbench-irqdma,b.prg]"])

    assert_includes problems, "testbench-irqdma: no shard runs interrupts/irqdma/test1.prg"
  end

  def test_a_row_two_shards_match_is_named
    problems = CIMatrix.unit_problems("a" => ["spinel:testbench[testbench-irqdma]"],
                                      "b" => ["spinel:testbench[testbench-irqdma,b.prg]"])

    assert_includes problems, "testbench-irqdma: interrupts/irqdma/test1b.prg runs on a, b"
  end

  def test_a_lorenz_stretch_no_shard_runs_is_named
    assert_equal ["lorenz: no shard runs 4"], CIMatrix.unit_problems("l" => ["spinel:lorenz[1,2,3]"])
  end

  def test_a_suite_no_shard_runs_is_named
    assert_includes CIMatrix.missing_suites("s" => ["spinel:sidtests[6581]"]), "sid-8580"
  end

  def test_a_left_out_suite_is_not_missing
    refute_includes CIMatrix.missing_suites({}), "testbench-c128-zex"
  end

  def test_testbench_all_runs_every_testbench_suite
    assert_equal Suites::SPINEL_TESTBENCH_SUITES, CIMatrix.runs("spinel:testbench[all]").map(&:first)
  end
end
