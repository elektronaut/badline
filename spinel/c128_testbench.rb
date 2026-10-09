# frozen_string_literal: true

# Runs C128 testbench tests the way bin/testbench --c128c64 and --c128 do, with the
# same Testbench::Execution, and prints what each one left behind for CRuby
# to score (Testbench::Engine): its exit code, and the display as palette
# indices for a screenshot test or the text screen for the others. Reads
# the tests from a list bin/testbench writes, one per line. Builds with
# Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/c128_testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/c128_testbench.rb -o tmp/spinel/c128_testbench
#   tmp/spinel/c128_testbench tests.txt

require "badline/core"
require "badline/c128"
require_relative "../test/testbench_c128_machine"

module Testbench
  HEX_DIGITS = "0123456789abcdef"

  # The mode a test's line names, :c128 or :c64.
  def self.mode_named(name) = name == "c128" ? :c128 : :c64

  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory, C128 model and mode, with an empty
  # cartridge or program for a test without one. A String in and a String
  # out, as spinel/testbench.rb's run_test.
  def self.run_c128_test(test)
    fields = test.chomp.split("\t")
    type = fields[1]
    cartridge = fields[3].empty? ? nil : fields[3]
    machine = c128_machine(fields[6], cartridge.nil?, mode_named(fields[7]))
    exit_code = Execution.new(machine).run(type != "exitcode", cartridge, fields[5], fields[4], fields[2].to_i)

    out = "test #{fields[0]}\n"
    out << "exit #{exit_code.nil? ? 'none' : exit_code.to_s}\n"
    out << "cycles #{machine.cycles}\n"
    if type == "exitcode"
      out << "text\n"
      screen_text(machine.ram).each { |line| out << line << "\n" }
    else
      out << "screen\n"
      screenshot(machine.vic).each do |row|
        row.each { |index| out << HEX_DIGITS[index] }
        out << "\n"
      end
    end
    out << "done\n"
  end
end

raise "Usage: c128_testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_c128_test(test)
  $stdout.flush
end
