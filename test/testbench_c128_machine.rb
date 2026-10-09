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
end
