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

  # The true drive a test line names, "1541" or "1571", or "" for none.
  def self.drive(fields) = fields.length > 8 ? fields[8] : ""

  # A machine for a test line: with its true drive when the line names
  # one, and a copy of its disk image at +scratch+ in the drive, since the
  # drive writes back to the image.
  def self.c128_line_machine(fields, cartridge, scratch)
    drive = drive(fields)
    return c128_machine(fields[6], cartridge.nil?, mode_named(fields[7])) if drive.empty?

    machine = c128_drive_machine(fields[6], mode_named(fields[7]), drive)
    disk = fields[9]
    copy = scratch + File.extname(disk)
    File.binwrite(copy, File.binread(disk))
    insert_disk(machine, copy)
    machine
  end

  # Runs one test on a fresh machine and returns what it left behind. The
  # test is a line of tab-separated fields: key, type, cycle budget,
  # cartridge path, program, directory, C128 model and mode, and the true
  # drive and its disk image, with an empty cartridge, program or drive for
  # a test without one. A String in and a String out, as
  # spinel/testbench.rb's run_test.
  def self.run_c128_test(test, scratch)
    fields = test.chomp.split("\t")
    type = fields[1]
    cartridge = fields[3].empty? ? nil : fields[3]
    machine = c128_line_machine(fields, cartridge, scratch)
    execution = Execution.new(machine, mount: drive(fields).empty?)
    exit_code = execution.run(type != "exitcode", cartridge, fields[5], fields[4], fields[2].to_i)

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
  print Testbench.run_c128_test(test, "#{ARGV[0]}.disk")
  $stdout.flush
end
