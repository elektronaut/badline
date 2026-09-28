# frozen_string_literal: true

require "spec_helper"

describe Badline::VIA::FastForward do
  # Two VIAs set up alike: one to run cycle by cycle, one to fast-forward.
  let(:vias) { Array.new(2) { Badline::VIA.new(start: 0x1800) } }

  def poke(addr, value) = vias.each { |via| via.poke(addr, value) }

  def start_timer1(value)
    poke(0x1804, value & 0xff)
    poke(0x1805, value >> 8)
  end

  def state(via) = [*via.idle_state, via.timer1, via.timer2]

  # Whether fast-forwarding +cycles+ leaves the VIA as running them does.
  def same_after?(cycles)
    stepped, forwarded = vias
    cycles.times { stepped.cycle! }
    forwarded.fast_forward(cycles)
    state(stepped) == state(forwarded)
  end

  it "runs free from power-on" do
    expect(vias.first.quiet_cycles).to eq(described_class::QUIET)
  end

  it "keeps both counters going" do
    expect([1, 255, 256, 0x1_0000, 0x2_3456].map { |cycles| same_after?(cycles) }).to all(be(true))
  end

  it "takes an unarmed timer 1 round its reloads" do
    start_timer1(3)
    vias.each { |via| 6.times { via.cycle! } } # the one-shot timeout disarms it
    expect([1, 2, 4, 5, 6, 11, 1000].map { |cycles| same_after?(cycles) }).to all(be(true))
  end

  it "picks up an unarmed timer 1 mid-reload" do
    start_timer1(3)
    vias.each { |via| 5.times { via.cycle! } }
    expect(same_after?(9)).to be(true)
  end

  it "runs an armed timer 1 up to its timeout" do
    start_timer1(0x1234)
    vias.each(&:cycle!)
    expect(vias.first.quiet_cycles).to eq(0x1234)
  end

  it "leaves the flag to the cycle after the quiet ones" do
    start_timer1(0x40)
    vias.each(&:cycle!)
    same_after?(vias.first.quiet_cycles)
    vias.each(&:cycle!)
    expect(vias.map(&:interrupt_flags)).to eq([0x40, 0x40])
  end

  it "has no quiet cycles while a timer loads" do
    start_timer1(0x40)
    expect(vias.first.quiet_cycles).to eq(0)
  end

  it "runs an armed timer 2 up to its underflow" do
    poke(0x1808, 0x10)
    poke(0x1809, 0x00)
    vias.each(&:cycle!)
    expect(vias.first.quiet_cycles).to eq(0x10)
  end

  it "runs timer 2 free while it counts PB6 pulses" do
    poke(0x180b, 0x20)
    poke(0x1808, 0x10)
    poke(0x1809, 0x00)
    vias.each { |via| 2.times { via.cycle! } }
    expect(vias.first.quiet_cycles).to eq(described_class::QUIET)
  end

  it "has no quiet cycles while the shift register shifts" do
    poke(0x180b, 0x08) # shift in under φ2
    poke(0x180a, 0x00)
    expect(vias.first.quiet_cycles).to eq(0)
  end

  it "has no quiet cycles while CA2 pulses" do
    poke(0x180c, 0x0a) # CA2 pulse output
    poke(0x1801, 0x00)
    expect(vias.first.quiet_cycles).to eq(0)
  end
end
