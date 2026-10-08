# frozen_string_literal: true

require "spec_helper"

# c128/d030tester, which measures from the frame it runs how many raster
# lines the TEST bit cuts and how long a frame takes. Its builds are
# C128-mode programs that switch to C64 mode as they start, so they run
# here from their machine code at $1C0E.
describe Badline::C128, :slow do
  subject(:machine) { described_class.new }

  def self.directory = File.expand_path("../../vendor/VICE-testprogs/c128/d030tester", __dir__)

  # Runs +build+ until it reports through $D7FF, and returns its "Lines
  # cut" and "Cycles Lost" readings and the frame's length in cycles.
  def readings(build)
    skip "VICE-testprogs not checked out" unless File.directory?(self.class.directory)

    start(File.binread(File.join(self.class.directory, "d030-#{build}.prg")).bytes)
    [screen(11, 20, 3), screen(11, 35, 4), screen(0, 33, 4)]
  end

  def start(program)
    done = false
    machine.install_debug_register { done = true }
    machine.run_cycles(machine.init_threshold)
    machine.load_prg(program)
    machine.cpu.step! until machine.cpu.boundary?
    machine.cpu.program_counter = 0x1c0e
    machine.run_until(machine.cycles + 6_000_000) { done }
  end

  def screen(row, col, length)
    Array.new(length) { |i| machine.ram.peek(0x0400 + (row * 40) + col + i).chr }.join.strip
  end

  # The readings each build's reference screenshot shows.
  {
    "2mhzmode0" => %w[00 0000 4CC8],
    "173_02_00" => %w[04 00FC 4CC8],
    "173_03_00" => %w[03 00BD 4CC8],
    "2ae_02_00" => %w[05 013B 4CC8],
    "32c_02_00" => %w[03 00BD 4CC8],
    "32c_03_00" => %w[02 007E 4CC8]
  }.each do |build, expected|
    it "reads what the reference shows for d030-#{build}" do
      expect(readings(build)).to eq(expected)
    end
  end
end
