# frozen_string_literal: true

# Runs VIC-20 testbench tests the way bin/testbench --vic20 does, with the
# same Testbench::Vic20Execution, and prints what each one left behind for
# CRuby to score (Testbench::Engine): its exit code, and the display as
# palette indices for a screenshot test or the text screen for the others.
# Reads the tests from a list bin/testbench writes, one per line. Builds
# with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/vic20_testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/vic20_testbench.rb -o tmp/spinel/vic20_testbench
#   tmp/spinel/vic20_testbench tests.txt

require "badline/core"
require "badline/vic20"
require_relative "../test/testbench_vic20_machine"

module Testbench
  HEX_DIGITS = "0123456789abcdef"

  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory and RAM configuration, with an
  # empty cartridge or program for a test without one. A String in and a
  # String out, as spinel/testbench.rb's run_test.
  def self.run_vic20_test(test)
    fields = test.chomp.split("\t")
    cartridge = fields[3].empty? ? nil : fields[3]
    machine = vic20_machine(fields[6].to_sym, cartridge.nil?)
    screenshot = fields[1] == "screenshot"
    exit_code = Vic20Execution.new(machine).run(screenshot, cartridge, fields[5], fields[4], fields[2].to_i)

    out = "test #{fields[0]}\n"
    out << "exit #{exit_code.nil? ? 'none' : exit_code.to_s}\n"
    out << "cycles #{machine.cycles}\n"
    out << (screenshot ? vic20_screen_record(machine) : vic20_text_record(machine))
    out << "done\n"
  end

  # The display as rows of hex digits, one a palette index.
  def self.vic20_screen_record(machine)
    out = +"screen\n"
    vic20_screenshot(machine).each do |row|
      row.each { |index| out << HEX_DIGITS[index] }
      out << "\n"
    end
    out
  end

  def self.vic20_text_record(machine)
    out = +"text\n"
    vic20_screen_text(machine).each { |line| out << line << "\n" }
    out
  end
end

raise "Usage: vic20_testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_vic20_test(test)
  $stdout.flush
end
