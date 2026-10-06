# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

# By init_threshold the VIC-20 has booted its KERNAL and BASIC to READY in
# every RAM configuration, and BASIC has counted the RAM it found.
describe Badline::Vic20, "#init_threshold", :slow do
  # The 23 rows of 22 characters on the screen the KERNAL set up, as text.
  def screen(machine)
    base = machine.ram.peek(0x0288) << 8
    Array.new(23) do |row|
      Array.new(22) { |col| character(machine.ram.peek(base + (row * 22) + col)) }.join.rstrip
    end
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  {
    unexpanded: [0x1e00, 3583], "3k": [0x1e00, 6655], "8k": [0x1000, 11_775],
    "16k": [0x1000, 19_967], "24k": [0x1000, 28_159], "32k": [0x1000, 28_159]
  }.each do |ram, (screen_start, bytes_free)|
    it "prints #{bytes_free} BYTES FREE and READY. on a screen at $#{screen_start.to_s(16).upcase} with #{ram}" do
      machine = described_class.new(ram:)
      machine.run_cycles(machine.init_threshold)
      expect([machine.ram.peek(0x0288) << 8, *screen(machine).first(5)])
        .to eq([screen_start, "**** CBM BASIC V2 ****", "", "#{bytes_free} BYTES FREE", "", "READY."])
    end
  end

  it "runs a line typed after boot" do
    machine = described_class.new
    machine.type_text("print 6*7\r")
    machine.run_cycles(machine.init_threshold + 100_000)
    expect(screen(machine)[5, 4]).to eq(["PRINT 6*7", " 42", "", "READY."])
  end
end
