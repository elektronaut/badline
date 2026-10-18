# frozen_string_literal: true

# Runs P500 testbench tests the way bin/testbench --cbm5x0 does, with the
# same Testbench::P500Execution, and prints what each one left behind for
# CRuby to score (Testbench::Engine): its exit code, and the text screen
# or, for a screenshot row, the picture.
# Reads the tests from a list bin/testbench writes, one per line. Builds
# with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/p500_testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/p500_testbench.rb -o tmp/spinel/p500_testbench
#   tmp/spinel/p500_testbench tests.txt

require "badline/core"
require "badline/cbm2"
require_relative "../test/support/testbench_p500_machine"
require_relative "../test/support/testbench_record"

module Testbench
  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory and model, with an empty cartridge
  # or program for a test without one. A String in and a String out, as
  # spinel/testbench.rb's run_test.
  def self.run_p500_test(test)
    fields = test.chomp.split("\t")
    cartridge = fields[3].empty? ? nil : fields[3]
    machine = p500_machine(fields[6], cartridge.nil?)
    screenshot = fields[1] == "screenshot"
    exit_code = P500Execution.new(machine).run(screenshot, cartridge, fields[5], fields[4], fields[2].to_i)
    return Record.screen(fields[0], exit_code, machine.cycles, screenshot(machine.vic)) if screenshot

    Record.text(fields[0], exit_code, machine.cycles, p500_screen_text(machine))
  end
end

raise "Usage: p500_testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_p500_test(test)
  $stdout.flush
end
