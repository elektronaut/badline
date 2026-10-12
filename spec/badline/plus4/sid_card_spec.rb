# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4::SIDCard do
  subject(:card) { described_class.new(clock, :mos6581) }

  let(:clock) { Struct.new(:cycles).new(0) }

  # Voice 3's sawtooth at frequency $0100 from a reset oscillator, OSC3
  # read `cycles` later.
  def osc3_after(cycles)
    { 0xfd4e => 0x00, 0xfd4f => 0x01, 0xfd52 => 0x08 }.each { |addr, value| card.poke(addr, value) }
    card.poke(0xfd52, 0x20)
    clock.cycles += cycles
    card.peek(0xfd5b)
  end

  it "counts the cycles that passed since it was last touched" do
    expect(osc3_after(256 * 69)).to eq(69)
  end

  it "runs a CPU access through the cycle it is in" do
    expect(osc3_after(256)).to eq(1)
  end

  it "counts on from the machine's cycle once restored" do
    clock.cycles = 1_000_000
    card.restored!
    expect(osc3_after(256)).to eq(1)
  end
end
