# frozen_string_literal: true

require "minitest/autorun"
require_relative "z80_single_step"

# SingleStepTests' Z80 cases, the first 100 of each opcode's file, or
# every case with Z80_SAMPLE=all.
class TestZ80 < Minitest::Test
  DIR = ENV["Z80_SAMPLE"] == "all" ? Z80SingleStep::FULL_DIR : Z80SingleStep::SAMPLE_DIR

  Z80SingleStep.files(DIR).each do |path|
    name = File.basename(path, ".json")

    define_method("test_#{name.tr(' ', '_')}") do
      tests = Z80SingleStep.cases(path)
      failures = tests.filter_map do |test|
        errors = Z80SingleStep.run(test)
        "#{test['name']}: #{errors.join('; ')}" unless errors.empty?
      end

      assert_empty failures, "#{failures.length} of #{tests.length} cases failed, the first: #{failures.first}"
    end
  end
end
