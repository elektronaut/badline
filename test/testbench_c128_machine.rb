# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --c128c64 and --c128: building
# the C128 a row asks for. Its tests run through the C64's
# Testbench::Execution, since either mode loads, types and reports through
# $D7FF as a C64 does, through the KERNAL traps of the mode it runs. It stays
# inside the Ruby subset Spinel compiles, so bin/testbench on CRuby and
# spinel/c128_testbench.rb on a Spinel build run each test the same way.
module Testbench
  # A C128 of the model named (Badline::C128::Model::ALL) that powers on in
  # +mode+, :c64 or :c128, booted up to the cycle where a program loads, or
  # left at power-on when +boot+ is false, for a cartridge that has to be in
  # before the first cycle.
  def self.c128_machine(model, boot, mode)
    machine = Badline::C128.new(model:, mode:)
    machine.run_cycles(machine.init_threshold) if boot
    machine
  end

  # A C128 as c128_machine boots one, with a true drive on the serial bus
  # that boots alongside it: +drive+ "1571" for the C128D's, or "1541".
  def self.c128_drive_machine(model, mode, drive)
    machine = Badline::C128.new(model:, mode:)
    if drive == "1541"
      machine.attach_drive1541(Badline::Drive1541.new)
    else
      machine.attach_drive1571(Badline::Drive1571.new)
    end
    machine.run_cycles(machine.init_threshold)
    machine
  end
end
