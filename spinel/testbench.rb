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
require "badline/region"
require "badline/addressable"
require "badline/memory"
require "badline/color_memory"
require "badline/rom"
require "badline/ram_expansion"
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
require "badline/via"
require "badline/sid"
require "badline/debug_register"
require "badline/reu"
require "badline/interrupts"
require "badline/traps"
require "badline/cpu"
require "badline/vic"
require "badline/keyboard_buffer"
require "badline/iec_bus"
require "badline/drive1541"
require "badline/computer"
require "badline/storage"
require "badline/cartridge"
require "badline/kernal_trap"
require "badline/chrout_trap"
require "badline/media"
require_relative "../test/testbench_machine"

module Testbench
  HEX_DIGITS = "0123456789abcdef"

  # The CIA and VIC-II models a test line names.
  def self.cia_model(name) = name == "mos6526a" ? :mos6526a : :mos6526
  def self.vic_model(name) = name == "mos8565" ? :mos8565 : :mos6569

  # The memory expansion a test line names, or nil for none.
  def self.expansion(fields) = fields.length > 8 && !fields[8].empty? ? fields[8] : nil

  # The video standard a test line names.
  def self.region(fields)
    name = fields.length > 9 ? fields[9] : ""
    if name == "ntsc" then :ntsc
    elsif name == "ntscold" then :ntscold
    else :pal
    end
  end

  # Whether a test line asks for the true drive.
  def self.drive?(fields) = fields.length > 10 && fields[10] == "drive"

  # The disk image a test line puts in the true drive, or nil for none.
  def self.disk(fields) = fields.length > 11 && !fields[11].empty? ? fields[11] : nil

  # A machine for a test line: booted with the true drive when the line
  # asks for it, with a copy of its disk image at +scratch+ in the drive,
  # since the drive writes back to the image.
  def self.test_machine(fields, cartridge, scratch)
    unless drive?(fields)
      return machine(cartridge, cia_model(fields[6]), vic_model(fields[7]), expansion(fields), region: region(fields))
    end

    computer = drive_machine(cia_model(fields[6]), vic_model(fields[7]))
    disk = disk(fields)
    if disk
      copy = scratch + File.extname(disk)
      File.binwrite(copy, File.binread(disk))
      insert_disk(computer, copy)
    end
    computer
  end

  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory, CIA model, VIC-II model, memory
  # expansion, video standard, "drive" for the true drive and its disk
  # image, with an empty cartridge, program, expansion, drive or disk for a
  # test without one. scratch is the path, less its extension, that a copy
  # of the disk image goes to. Strings in and a String out, so that
  # `spin ext` can export it to CRuby as it stands.
  def self.run_test(test, scratch)
    fields = test.chomp.split("\t")
    type = fields[1]
    cartridge = fields[3].empty? ? nil : fields[3]
    computer = test_machine(fields, cartridge, scratch)
    execution = Execution.new(computer, mount: !drive?(fields))
    exit_code = execution.run(type != "exitcode", cartridge, fields[5], fields[4], fields[2].to_i)

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
  print Testbench.run_test(test, "#{ARGV[0]}.disk")
  $stdout.flush
end
