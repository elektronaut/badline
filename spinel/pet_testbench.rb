# frozen_string_literal: true

# Runs PET testbench tests the way bin/testbench --pet and --pet-discrete
# do, with the same Testbench::PETExecution, and prints what each one left
# behind for CRuby to score (Testbench::Engine): its exit code, and the
# text screen or, for a screenshot row, the picture. Reads the tests from a list bin/testbench writes, one per
# line. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/pet_testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/pet_testbench.rb -o tmp/spinel/pet_testbench
#   tmp/spinel/pet_testbench tests.txt

require "badline/core"
require_relative "../test/support/testbench_pet_machine"
require_relative "../test/support/testbench_record"

module Testbench
  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # program, directory and model. A String in and a String out, as
  # spinel/testbench.rb's run_test.
  def self.run_pet_test(test)
    fields = test.chomp.split("\t")
    machine = pet_machine(fields[5])
    exit_code = PETExecution.new(machine).run(fields[4], fields[3], fields[2].to_i)

    return Record.screen(fields[0], exit_code, machine.cycles, pet_screenshot(machine)) if fields[1] == "screenshot"

    Record.text(fields[0], exit_code, machine.cycles, pet_screen_text(machine))
  end
end

raise "Usage: pet_testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_pet_test(test)
  $stdout.flush
end
