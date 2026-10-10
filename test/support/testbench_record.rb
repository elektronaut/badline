# frozen_string_literal: true

module Testbench
  # The record a Spinel testbench harness prints for a test, which
  # Testbench::Engine (testbench_engine.rb) parses on CRuby. It stays
  # inside the Ruby subset Spinel compiles, so spinel/testbench.rb,
  # spinel/vic20_testbench.rb and spinel/c128_testbench.rb write their
  # records with it:
  #
  #   test KEY
  #   exit CODE|none
  #   cycles CYCLES
  #   text            then the lines of the text screen, for an exitcode test
  #   screen          or the rows of the display as hex palette indices
  #   done
  module Record
    HEX_DIGITS = "0123456789abcdef"

    # The record for an exitcode test, with the text screen as lines.
    def self.text(key, exit_code, cycles, lines)
      out = header(key, exit_code, cycles)
      out << "text\n"
      lines.each { |line| out << line << "\n" }
      out << "done\n"
    end

    # The record for a screenshot test, with the display as rows of
    # palette indices.
    def self.screen(key, exit_code, cycles, rows)
      out = header(key, exit_code, cycles)
      out << "screen\n"
      rows.each do |row|
        row.each { |index| out << HEX_DIGITS[index] }
        out << "\n"
      end
      out << "done\n"
    end

    def self.header(key, exit_code, cycles)
      out = "test #{key}\n"
      out << "exit #{exit_code.nil? ? 'none' : exit_code.to_s}\n"
      out << "cycles #{cycles}\n"
    end
  end
end
