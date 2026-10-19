# frozen_string_literal: true

require "spec_helper"

describe Badline::KIM1::Sound do
  let(:kim) { Badline::KIM1.new }
  let(:sound) { kim.sound_source }

  # Toggles U2's PB7, or with `pa0` U3's PA0, every 500 cycles, a 1 kHz
  # square wave, for `cycles` cycles, and returns the samples.
  def square_wave(cycles, pa0: false)
    register = pa0 ? 0x1700 : 0x1742
    kim.poke(pa0 ? 0x1701 : 0x1743, pa0 ? 0x01 : 0x80)
    sound.record(rate: 44_100)
    (cycles / 500).times do |half|
      kim.poke(register, half.even? ? 0xff : 0x00)
      500.times { sound.cycle! }
    end
    sound.drain_samples
  end

  it "plays U2's PB7" do
    expect(square_wave(10_000).max).to be > 10_000
  end

  it "keeps quiet on U3's PA0 without the speaker" do
    expect(square_wave(10_000, pa0: true).map(&:abs).max).to be < 100
  end

  it "plays U3's PA0 with the speaker wired" do
    kim.speaker = true
    expect(square_wave(10_000, pa0: true).max).to be > 10_000
  end

  it "is clocked by the machine while it records" do
    sound.record(rate: 44_100)
    kim.run_cycles(1_000)
    expect(sound.drain_samples.size).to eq(44)
  end
end
