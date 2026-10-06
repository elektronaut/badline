# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::Sound::Output do
  subject(:output) { described_class.new(clock_hz: 1_108_405, rate: 44_100, level: 0) }

  # The samples of a step from 0 to `level`, held for `cycles` cycles.
  def step(level, cycles)
    output.hold(level, cycles)
    output.drain
  end

  it "closes a sample every 1/44100 s of the clock" do
    expect(step(0, 1_108_405 * 3).size).to eq(44_100 * 3)
  end

  it "takes a settled level as the line" do
    settled = described_class.new(clock_hz: 1_108_405, rate: 44_100, level: 300)
    settled.hold(300, 100_000)
    expect(settled.drain.uniq).to eq([0])
  end

  # Pinned by xvic: a bass voice turned on at volume 15 rises and decays
  # as RC stages at 1,417 and 158.0 Hz do, fitted to its recording with an
  # RMS error of 6 against a peak of 11,280. Ours fit 1,420 and 157.6 Hz.
  describe "a step" do
    let(:samples) { step(570, 44_100) }

    it "peaks about 0.25 ms in, past the low-pass" do
      expect(samples.index(samples.max)).to eq(11)
    end

    it "decays to 1/e about 1 ms after its peak, through the high-pass" do
      top = samples.max
      expect(samples.drop(11).index { |sample| sample < top / Math::E }).to be_between(44, 56)
    end

    it "settles back to the line" do
      expect(samples.last(100).uniq).to eq([0])
    end
  end
end
