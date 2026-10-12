# frozen_string_literal: true

# Runs 264 series testbench tests the way bin/testbench --plus4 and --c16
# do, with the same Testbench::Plus4Execution, and prints what each one
# left behind for CRuby to score (Testbench::Engine): its exit code and the
# text screen, or the picture for a screenshot test. Reads the tests from a list bin/testbench writes, one per
# line. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/plus4_testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/plus4_testbench.rb -o tmp/spinel/plus4_testbench
#   tmp/spinel/plus4_testbench tests.txt

require "badline/core"
require "badline/plus4"
require_relative "../test/support/testbench_plus4_machine"
require_relative "../test/support/testbench_record"

module Testbench
  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory, model, RAM expansion and "border"
  # for a test that reports through the border colour, with an empty
  # cartridge, program or RAM expansion for a test without one. A String
  # in and a String out, as spinel/testbench.rb's run_test.
  def self.run_plus4_test(test)
    fields = test.chomp.split("\t")
    cartridge = fields[3].empty? ? nil : fields[3]
    ram_expansion = fields.length > 7 ? fields[7] : ""
    machine = plus4_machine(fields[6], cartridge.nil?, ram_expansion)
    screenshot = fields[1] == "screenshot"
    execution = Plus4Execution.new(machine, border: fields.length > 8 && fields[8] == "border")
    exit_code = execution.run(screenshot, cartridge, fields[5], fields[4], fields[2].to_i)
    return Record.wide_screen(fields[0], exit_code, machine.cycles, plus4_screenshot(machine)) if screenshot

    Record.text(fields[0], exit_code, machine.cycles, plus4_screen_text(machine))
  end
end

raise "Usage: plus4_testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_plus4_test(test)
  $stdout.flush
end
