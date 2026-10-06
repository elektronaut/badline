# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

# VIC20/split-tests/timing on a PAL VIC-20, against the memory dumps it
# left on real 6561s. For 256 cycles in a row, four lines into the text
# window, the program reads $9003, $9004, and $9100 and $9200, where no
# chip answers and the V-bus's last byte comes back: the VIC's fetch where
# it fetches, the CPU's own last byte where it doesn't. Pinned here: when
# the raster count moves, and the cycle of each matrix and character
# fetch.
#
# The dumps of two chips differ in the cycles outside the window, where
# the 6561E (dump6561e.prg) leaves the CPU's byte and a later 6561-101
# (dump6561-101.prg) reads $20. Badline follows the 6561E.
describe Badline::Vic20::VIC, :slow do
  def self.directory = File.expand_path("../../../vendor/VICE-testprogs/VIC20/split-tests/timing", __dir__)

  def self.results
    @results ||= measure(File.binread(File.join(directory, "timing.prg")).bytes)
  end

  # Loads the program as LOAD and RUN would, and runs it a frame at a
  # time until it has written its stability count at $17E8, once the
  # measurements are done.
  def self.measure(program)
    machine = Badline::Vic20.new
    machine.run_cycles(machine.init_threshold)
    load_program(machine, program)
    machine.run_cycles(71 * 312) while waiting?(machine)
    Array.new(0x440) { |offset| machine.ram.peek(0x17c0 + offset) }
  end

  # The count is zero from when the program clears its buffer, well inside
  # the first 5M cycles, until it writes it.
  def self.waiting?(machine)
    cycles = machine.cycles
    cycles < 30_000_000 && (cycles < 5_000_000 || machine.ram.peek(0x17e8).zero?)
  end

  def self.load_program(machine, program)
    ram = machine.ram
    ram.write(0x1001, program[2..])
    finish = 0x1001 + program.length - 2
    [0x2d, 0xae].each { |pointer| ram.write(pointer, [finish & 0xff, finish >> 8]) }
    machine.type_text("run\r")
  end

  def dump(name) = File.binread(File.join(directory, "dumps", name)).bytes[2..]

  def measured(test, results) = results[0x40 + (test * 256), 256]

  def directory = self.class.directory

  before { skip "VICE-testprogs not checked out" unless File.directory?(directory) }

  {
    "$9003, the raster line's bit 0" => 0, "$9004, the raster line's bits 8-1" => 1,
    "$9100, the V-bus" => 2, "$9200, the V-bus" => 3
  }.each do |register, test|
    it "reads #{register} as the 6561E did" do
      expect(measured(test, self.class.results)).to eq(measured(test, dump("dump6561e.prg")))
    end
  end

  it "keeps the raster steady, as the stability guard counts it" do
    expect(self.class.results[40]).to eq(1)
  end
end
