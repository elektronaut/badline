# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::Sound do
  subject(:sound) { described_class.new(via) }

  let(:via) { Badline::PET::VIA.new(start: 0xe840) }

  # Runs the VIA and the sound `cycles` cycles, as the PET does, then
  # drains the samples.
  def run(cycles)
    cycles.times do
      via.cycle!
      sound.cycle! if sound.recording?
    end
    sound.drain_samples
  end

  # Free-running shift-out under timer 2, latch `latch`, rotating `byte`.
  def free_run(latch, byte)
    via.poke(0xe84b, 0x10)
    via.poke(0xe848, latch)
    via.poke(0xe84a, byte)
  end

  def sign_changes(samples) = samples.each_cons(2).count { |earlier, later| (earlier >= 0) != (later >= 0) }

  it "collects nothing until recorded" do
    free_run(14, 0x0f)
    expect(run(2_000)).to be_empty
  end

  context "when recorded at 44,100 Hz" do
    before { sound.record(rate: 44_100, clock_hz: 1_000_000) }

    it "closes a sample every 1,000,000/44,100 cycles" do
      expect(run(100_000).size).to eq(4410)
    end

    it "is silent with CB2 left as an input" do
      expect(run(10_000).uniq).to eq([0])
    end

    # Each bit lasts two timer 2 underflows, latch + 2 cycles apart, so
    # $0F rotating under a latch of 14 is a square wave of 256 cycles.
    it "plays the free-running shift register as a square wave of 16 underflows a byte" do
      free_run(14, 0x0f)
      run(2_000)
      expect(sign_changes(run(64_000))).to be_within(2).of(500)
    end

    it "plays CB2 held low and high by the PCR as a step that settles to silence" do
      run(1_000)
      via.poke(0xe84c, 0xc0)
      expect(run(1_000).min).to be < -10_000
    end

    it "settles a CB2 held low to silence" do
      via.poke(0xe84c, 0xc0)
      run(50_000)
      expect(run(1_000).map(&:abs).max).to be < 10
    end
  end

  # Pinned by PET/samples/sample.prg, which plays 4-bit samples as how
  # many of each byte's bits are high under a latch of 1: the sample's
  # level is the share of the cycles CB2 spends high.
  context "with the shift register's bits as a level" do
    before do
      sound.record(rate: 44_100, clock_hz: 1_000_000)
      free_run(1, 0x80)
      run(2_000)
    end

    # The mean sample over 960 cycles, twenty bytes, of `byte`.
    def mean(byte)
      via.poke(0xe84a, byte)
      samples = run(960)
      samples.sum.fdiv(samples.size)
    end

    # How far the mean sample moves between `low` and `high`, alternated
    # until the output stage settles into the alternation.
    def step(low, high)
      means = Array.new(16) { |half| mean(half.even? ? low : high) }.last(2)
      means.last - means.first
    end

    it "steps seven times as far from one bit high to eight as from one to two" do
      ratio = step(0x80, 0xff).fdiv(step(0x80, 0x88))
      expect(ratio).to be_within(0.2).of(7)
    end
  end
end
