# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4 do
  # The 25 rows of 40 characters on the screen at $0C00, as text.
  def screen(machine)
    Array.new(25) do |row|
      Array.new(40) { |col| character(machine.ram.peek(0x0c00 + (row * 40) + col)) }.join.rstrip
    end
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  def booted(**)
    described_class.new(**).tap { |machine| machine.run_cycles(machine.init_threshold) }
  end

  it "starts at the KERNAL's reset entry" do
    expect(described_class.new.cpu.program_counter).to eq(0xfff6)
  end

  it "refuses a RAM size it can't fit" do
    expect { described_class.new(ram: 48) }.to raise_error(ArgumentError, /48K/)
  end

  it "takes c116 for the C16" do
    expect(described_class.new(model: "c116").model).to eq(described_class::Model::C16)
  end

  {
    "plus4" => [nil, ["COMMODORE BASIC V3.5 60671 BYTES FREE", "3-PLUS-1 ON KEY F1", "", "READY."]],
    "plus4ntsc" => [nil, ["COMMODORE BASIC V3.5 60671 BYTES FREE", "3-PLUS-1 ON KEY F1", "", "READY."]],
    "c16" => [nil, ["COMMODORE BASIC V3.5 12277 BYTES FREE", "", "READY."]],
    "c16ntsc" => [nil, ["COMMODORE BASIC V3.5 12277 BYTES FREE", "", "READY."]],
    "c116" => [32, ["COMMODORE BASIC V3.5 28661 BYTES FREE", "", "READY."]]
  }.each do |model, (ram, lines)|
    it "boots the #{model}#{" with #{ram}K" if ram} to READY by its init threshold" do
      expect(screen(booted(model:, ram:)).map(&:strip).drop(1).first(lines.length)).to eq(lines)
    end
  end

  it "runs a line typed after boot" do
    machine = described_class.new(model: "c16")
    machine.type_text("print 6*7\r")
    machine.run_cycles(machine.init_threshold + 100_000)
    expect(screen(machine)[4, 3]).to eq(["PRINT 6*7", " 42", ""])
  end

  # The jiffy clock counts sixtieths of a second, so the PAL KERNAL counts
  # six jiffies every five frames.
  it "runs the KERNAL's jiffy clock off the raster interrupt" do
    machine = booted(model: "c16")
    before = machine.ram.peek(0xa5)
    machine.run_cycles(57 * 312 * 10)
    expect((machine.ram.peek(0xa5) - before) & 0xff).to eq(12)
  end

  it "reads a held key through the keyboard latch" do
    machine = booted(model: "c16")
    machine.keyboard.press(:a)
    machine.run_cycles(57 * 312 * 4)
    expect(screen(machine)[4]).to eq("A")
  end
end
