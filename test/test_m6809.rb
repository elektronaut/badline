# frozen_string_literal: true

require "minitest/autorun"
require "badline/chips/m6809"
require_relative "support/m6809_single_step"

# neetandev/m6809's cases, the first 100 of each opcode's file, or every
# case with M6809_SAMPLE=all.
class TestM6809 < Minitest::Test
  M6809Vectors.manifest.each_key do |stem|
    define_method("test_#{stem.tr(' ', '_')}") do
      tests = M6809SingleStep.cases(M6809Vectors.path(stem))
      failures = tests.filter_map do |test|
        errors = M6809SingleStep.run(test, Badline::Chips::M6809)
        "#{test.name}: #{errors.join('; ')}" unless errors.empty?
      end

      assert_empty failures, "#{failures.length} of #{tests.length} cases failed, the first: #{failures.first}"
    end
  end
end
