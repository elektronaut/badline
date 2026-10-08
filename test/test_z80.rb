# frozen_string_literal: true

require "minitest/autorun"
require_relative "z80_single_step"

# SingleStepTests' Z80 cases, a sample of each opcode's file: 100 cases
# unless Z80_SAMPLE names another count, or "all" for every case.
class TestZ80 < Minitest::Test
  SAMPLE = ENV.fetch("Z80_SAMPLE", "100")

  Z80SingleStep.files.each do |path|
    name = File.basename(path, ".json")

    define_method("test_#{name.tr(' ', '_')}") do
      tests = Z80SingleStep.cases(path, sample: SAMPLE == "all" ? nil : Integer(SAMPLE))
      failures = tests.filter_map do |test|
        errors = Z80SingleStep.run(test)
        "#{test['name']}: #{errors.join('; ')}" unless errors.empty?
      end

      assert_empty failures, "#{failures.length} of #{tests.length} cases failed, the first: #{failures.first}"
    end
  end
end
