# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Envelope do
  subject(:envelope) { described_class.new }

  # The fastest rate period, used by every ADSR nibble of 0.
  let(:period) { described_class::PERIODS[0] }

  def run(cycles)
    cycles.times { envelope.cycle! }
  end

  # Gate on at the fastest attack and run the 255 steps up to full scale.
  def attack_to_peak
    envelope.control = 0x01
    run(255 * period)
  end

  # Peak the envelope at the slowest release, then swap the release rate in.
  def release_at_peak(sustain_release)
    envelope.sustain_release = 0xff
    attack_to_peak
    envelope.control = 0x00
    envelope.sustain_release = sustain_release
  end

  describe "at power on" do
    it "is silent" do
      expect(envelope.output).to eq(0x00)
    end

    it "sits in release" do
      expect(envelope.state).to eq(:release)
    end

    it "stays frozen without a gate" do
      run(10_000)
      expect(envelope.output).to eq(0x00)
    end
  end

  describe "attack" do
    before { envelope.control = 0x01 }

    it "enters the attack state on the gate edge" do
      expect(envelope.state).to eq(:attack)
    end

    it "does not step before the rate period elapses" do
      run(period - 1)
      expect(envelope.counter).to eq(0x00)
    end

    it "steps once per rate period" do
      run(period * 3)
      expect(envelope.counter).to eq(0x03)
    end

    it "rises linearly, ignoring the exponential divider" do
      run(period * 200)
      expect(envelope.counter).to eq(200)
    end

    it "reaches full scale" do
      attack_to_peak
      expect(envelope.counter).to eq(0xff)
    end

    it "falls through to decay at full scale" do
      attack_to_peak
      expect(envelope.state).to eq(:decay_sustain)
    end
  end

  describe "decay" do
    before do
      envelope.sustain_release = 0x80
      attack_to_peak
    end

    it "steps down one rate period after the peak" do
      run(period)
      expect(envelope.counter).to eq(0xfe)
    end

    it "holds at the sustain level" do
      run(period * 500)
      expect(envelope.counter).to eq(0x88)
    end

    it "keeps the sustain level in both nibbles" do
      envelope.sustain_release = 0x30
      run(period * 500)
      expect(envelope.counter).to eq(0x33)
    end
  end

  describe "exponential divider" do
    before do
      envelope.sustain_release = 0x00
      attack_to_peak
      run(period * (0xff - 0x5d))
    end

    it "reaches the first breakpoint on the linear rate" do
      expect(envelope.counter).to eq(0x5d)
    end

    it "skips a rate period below $5d" do
      run(period)
      expect(envelope.counter).to eq(0x5d)
    end

    it "steps every second rate period below $5d" do
      run(period * 2)
      expect(envelope.counter).to eq(0x5c)
    end
  end

  describe "release" do
    before do
      envelope.sustain_release = 0xf0
      attack_to_peak
      envelope.control = 0x00
    end

    it "enters the release state on the gate edge" do
      expect(envelope.state).to eq(:release)
    end

    it "steps down at the release rate" do
      run(period)
      expect(envelope.counter).to eq(0xfe)
    end

    it "freezes once it reaches zero" do
      run(period * 100_000)
      expect(envelope.counter).to eq(0x00)
    end

    it "unfreezes on the next gate edge" do
      run(period * 100_000)
      envelope.control = 0x01
      run(period)
      expect(envelope.counter).to eq(0x01)
    end
  end

  describe "rate register writes" do
    it "picks up a new attack rate while attacking" do
      envelope.attack_decay = 0xf0
      envelope.control = 0x01
      envelope.attack_decay = 0x00
      run(period)
      expect(envelope.counter).to eq(0x01)
    end

    it "picks up a new decay rate while decaying" do
      envelope.attack_decay = 0x0f
      attack_to_peak
      envelope.attack_decay = 0x00
      run(period)
      expect(envelope.counter).to eq(0xfe)
    end

    it "picks up a new release rate while releasing" do
      release_at_peak(0xf0)
      run(period)
      expect(envelope.counter).to eq(0xfe)
    end
  end

  # Gate on at the slowest attack, run 1000 cycles into the period, then
  # drop to the fastest. That leaves the rate counter well past its new
  # period.
  describe "ADSR delay bug" do
    before do
      envelope.attack_decay = 0xf0
      envelope.control = 0x01
      run(1000)
      envelope.attack_decay = 0x00
    end

    it "does not step at the new period" do
      run(period)
      expect(envelope.counter).to eq(0x00)
    end

    it "steps once the rate counter has wrapped" do
      run(0x8000 - 1000 + period - 1)
      expect(envelope.counter).to eq(0x01)
    end

    it "is still waiting one cycle earlier" do
      run(0x8000 - 1000 + period - 2)
      expect(envelope.counter).to eq(0x00)
    end
  end
end
