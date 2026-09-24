# frozen_string_literal: true

# Runs VICE testbench tests the way bin/testbench does, with the same
# Testbench::Execution, and prints what each one left behind for CRuby to
# score (Testbench::Engine): its exit code, and the display as palette
# indices for a screenshot test or the text screen for the others. Reads
# the tests from a list bin/testbench writes, one per line. Builds with
# Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/testbench.rb tests.txt
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/testbench.rb -o tmp/spinel/testbench
#   tmp/spinel/testbench tests.txt

require "badline/version"
require "badline/integer_helper"
require "badline/addressable"
require "badline/memory"
require "badline/color_memory"
require "badline/rom"
require "badline/address_bus"
require "badline/instruction"
require "badline/instruction_set"
require "badline/status"
require "badline/keyboard"
require "badline/joystick"
require "badline/control_ports"
require "badline/input"
require "badline/cycleable"
require "badline/datasette"
require "badline/time_of_day"
require "badline/cia"
require "badline/sid"
require "badline/debug_register"
require "badline/interrupts"
require "badline/traps"
require "badline/cpu"
require "badline/vic"
require "badline/keyboard_buffer"
require "badline/computer"
require "badline/storage"
require "badline/cartridge"
require "badline/kernal_trap"
require "badline/chrout_trap"
require "badline/media"
require_relative "../test/testbench_machine"
require_relative "debug_register"

module Testbench
  HEX_DIGITS = "0123456789abcdef"

  # The CIA model a test line names.
  def self.cia_model(name) = name == "mos6526a" ? :mos6526a : :mos6526

  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory and CIA model, with an empty
  # cartridge or program for a test without one. A String in and a String
  # out, so that `spin ext` can export it to CRuby as it stands.
  def self.run_test(test)
    fields = test.chomp.split("\t")
    type = fields[1]
    cartridge = fields[3].empty? ? nil : fields[3]
    computer = machine(cartridge, cia_model(fields[6]))
    exit_code = Execution.new(computer).run(type != "exitcode", cartridge, fields[5], fields[4], fields[2].to_i)

    out = "test #{fields[0]}\n"
    out << "exit #{exit_code.nil? ? 'none' : exit_code.to_s}\n"
    out << "cycles #{computer.cycles}\n"
    if type == "exitcode"
      out << "text\n"
      screen_text(computer.ram).each { |line| out << line << "\n" }
    else
      out << "screen\n"
      screenshot(computer.vic).each do |row|
        row.each { |index| out << HEX_DIGITS[index] }
        out << "\n"
      end
    end
    out << "done\n"
  end
end

raise "Usage: testbench tests.txt" if ARGV.empty?

File.read(ARGV[0]).each_line do |test|
  print Testbench.run_test(test)
  $stdout.flush
end
