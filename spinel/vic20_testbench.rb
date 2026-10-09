# frozen_string_literal: true

# Runs VIC-20 testbench tests the way bin/testbench --vic20 does, with the
# same Testbench::Vic20Execution, and prints what each one left behind for
# CRuby to score (Testbench::Engine): its exit code and the text screen.
# Reads the tests from a list bin/testbench writes, one per line. Builds
# with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/vic20_testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/vic20_testbench.rb -o tmp/spinel/vic20_testbench
#   tmp/spinel/vic20_testbench tests.txt

require "badline/core"
require "badline/vic20"
require_relative "../test/testbench_vic20_machine"
require_relative "../test/testbench_record"

module Testbench
  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory and RAM configuration, with an
  # empty cartridge or program for a test without one. A String in and a
  # String out, as spinel/testbench.rb's run_test.
  def self.run_vic20_test(test)
    fields = test.chomp.split("\t")
    cartridge = fields[3].empty? ? nil : fields[3]
    machine = vic20_machine(fields[6].to_sym, cartridge.nil?)
    exit_code = Vic20Execution.new(machine).run(cartridge, fields[5], fields[4], fields[2].to_i)

    Record.text(fields[0], exit_code, machine.cycles, vic20_screen_text(machine))
  end
end

raise "Usage: vic20_testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_vic20_test(test)
  $stdout.flush
end
