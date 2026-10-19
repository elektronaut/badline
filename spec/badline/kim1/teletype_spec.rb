# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/taken_once"

describe Badline::KIM1::Teletype do
  subject(:teletype) { described_class.new(panel, baud: 9600) }

  let(:panel) { Struct.new(:tty_in_high).new(true) }

  # The line's level at each bit's middle, from the start bit on, while
  # it sends `byte` with the printer line idle.
  def sent_bits(byte)
    teletype.type(byte.chr)
    levels = []
    (0...1_200).each do |cycle|
      teletype.cycle!(cycle, true)
      levels << teletype.line_high? if (cycle % 104) == 52
    end
    levels.first(11)
  end

  # Drives the printer line with `byte` framed at 9600 baud from cycle 100.
  def print_byte(byte)
    bits = [false] + Array.new(8) { |bit| byte.anybits?(1 << bit) } + [true]
    (0...1_400).each do |cycle|
      index = ((cycle - 100) / 104.1667).floor
      teletype.cycle!(cycle, index.negative? || index >= bits.size ? true : bits[index])
    end
    teletype.output
  end

  it "sends a start bit, the data from the lowest bit and two stop bits" do
    expect(sent_bits(0x41)).to eq([false, true, false, false, false, false, false, true, false, true, true])
  end

  it "pulls the panel's line in low with its own" do
    teletype.type("A")
    teletype.cycle!(0, true)
    expect(panel.tty_in_high).to be(false)
  end

  it "types letters in capitals" do
    expect(sent_bits(0x61)[6]).to be(false)
  end

  it "prints what comes in on the printer line, without bit 7" do
    expect(print_byte(0xcb)).to eq("K")
  end

  it "takes a start bit high again by its middle for a glitch" do
    teletype.cycle!(0, true)
    teletype.cycle!(1, false)
    (2..2_000).each { |cycle| teletype.cycle!(cycle, true) }
    expect(teletype.output).to eq("")
  end

  it "sends RUBOUT after a reset" do
    teletype.reset!(0)
    expect(teletype.busy?).to be(true)
  end

  it "refuses a baud a teletype here doesn't run at" do
    expect { teletype.baud = 19_200 }.to raise_error(ArgumentError, /19200/)
  end

  # The User Manual's section 2.6: after RS and RUBOUT, the monitor prints
  # its prompt, and an address and a space open it.
  describe "on a KIM-1" do
    let(:output) do
      TakenOnce.fetch("KIM-1 teletype 0200") do
        kim = Badline::KIM1.new(tty: true)
        kim.type_text("0200 ")
        kim.run_cycles(1_000) until kim.teletype.output.end_with?("0200 00 ") || kim.cycles > 400_000
        kim.teletype.output.delete("\x00")
      end
    end

    it "prints the prompt after the RUBOUT it sends" do
      expect(output).to start_with("\x7f\r\nKIM\r\n0000 00 ")
    end

    it "opens the address typed" do
      expect(output).to end_with("0200 \r\n0200 00 ")
    end
  end
end
