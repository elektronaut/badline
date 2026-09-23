# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Envelope do
  subject(:envelope) { described_class.new }

  # The fastest rate period, used by every ADSR nibble of 0. The counter
  # matches its comparison value, then takes a cycle to reset.
  let(:period) { described_class::PERIODS[0] + 1 }

  # From power on the rate counter matches on the ninth cycle and resets on
  # the tenth, and the attack step lands two cycles after that.
  let(:first_step) { period + 3 }

  def run(cycles)
    cycles.times { envelope.cycle! }
  end

  # Gate on at the fastest attack and run the 255 steps up to full scale.
  def attack_to_peak
    envelope.control = 0x01
    run(first_step + (254 * period))
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

  # Pinned by env_test/env_test_ra_0100, env_test_adra_1 and
  # env_test_adra_2: the new state takes two cycles to land.
  describe "gate edge" do
    before { envelope.control = 0x01 }

    it "runs the decay state for a cycle" do
      run(1)
      expect(envelope.state).to eq(:decay_sustain)
    end

    it "enters the attack state on the second cycle" do
      run(2)
      expect(envelope.state).to eq(:attack)
    end
  end

  # Pinned by env_test/env_test_ra_0100: the decay rate runs for the
  # first cycle after the gate edge. With the counter one cycle short of
  # the attack period, a slower decay rate lets it run past, into the ADSR
  # delay bug.
  describe "gate edge on the cycle before the attack period" do
    before do
      envelope.attack_decay = 0x01
      run(period - 1)
      envelope.control = 0x01
    end

    it "misses the attack period" do
      run(period * 4)
      expect(envelope.counter).to eq(0x00)
    end
  end

  # Pinned by env_test (all seven): the step lands two cycles after the
  # rate counter resets.
  describe "attack" do
    before { envelope.control = 0x01 }

    it "does not step before the rate counter has reset and the step has landed" do
      run(first_step - 1)
      expect(envelope.counter).to eq(0x00)
    end

    it "steps once per rate period" do
      run(first_step + (period * 2))
      expect(envelope.counter).to eq(0x03)
    end

    it "rises linearly, ignoring the exponential divider" do
      run(first_step + (period * 199))
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

  # Pinned by env_test (all seven): ENV3 samples the counter at the start
  # of the cycle.
  describe "#env3" do
    before do
      envelope.control = 0x01
      run(first_step)
    end

    it "reads the counter a cycle late" do
      expect(envelope.env3).to eq(0x00)
    end

    it "catches up on the next cycle" do
      run(1)
      expect(envelope.env3).to eq(0x01)
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

  # Pinned by env_test (all seven): a divider above 1 delays the step one
  # more cycle.
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

    it "is still waiting on the cycle the second period ends" do
      run(period * 2)
      expect(envelope.counter).to eq(0x5d)
    end

    it "steps a cycle after every second rate period below $5d" do
      run((period * 2) + 1)
      expect(envelope.counter).to eq(0x5c)
    end
  end

  describe "release" do
    before do
      envelope.sustain_release = 0xf0
      attack_to_peak
      envelope.control = 0x00
    end

    it "enters the release state a cycle after the gate edge" do
      run(1)
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
      run(period * 2)
      expect(envelope.counter).to be_positive
    end
  end

  # Pinned by env_test/env_test_ar_1 and env_test_ar_2: with a step in
  # flight, releasing the gate waits a cycle more before the rate switches.
  describe "gate falling with a step in flight" do
    before do
      envelope.attack_decay = 0x0f
      envelope.control = 0x01
      run(period + 1)
      envelope.control = 0x00
    end

    it "lets the attack step land" do
      run(2)
      expect(envelope.counter).to eq(0x01)
    end

    it "is still attacking two cycles later" do
      run(2)
      expect(envelope.state).to eq(:attack)
    end

    it "releases on the third" do
      run(3)
      expect(envelope.state).to eq(:release)
    end
  end

  # Pinned by env_test/env_test_adra_1 and env_test_adra_2 (and the two
  # ra tests, whose sync releases through it): a gate edge on the cycle the
  # rate counter matches steps the attack two cycles later, without waiting
  # out a period. Released from the peak, the counter matches six cycles
  # after the first release step.
  describe "gate rising as the rate counter matches" do
    before do
      envelope.sustain_release = 0xf0
      attack_to_peak
      envelope.control = 0x00
      run(period + 6)
      envelope.control = 0x01
    end

    it "does not step on the first cycle" do
      run(1)
      expect(envelope.counter).to eq(0xfe)
    end

    it "steps up on the second" do
      run(2)
      expect(envelope.counter).to eq(0xff)
    end
  end

  describe "rate register writes" do
    context "when attacking" do
      before do
        envelope.attack_decay = 0xf0
        envelope.control = 0x01
        run(2)
      end

      it "picks up a new attack rate" do
        envelope.attack_decay = 0x00
        run(first_step - 2)
        expect(envelope.counter).to eq(0x01)
      end
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
      run(0x8000 - 1000 + period + 2)
      expect(envelope.counter).to eq(0x01)
    end

    it "is still waiting one cycle earlier" do
      run(0x8000 - 1000 + period + 1)
      expect(envelope.counter).to eq(0x00)
    end
  end

  # Cycle by cycle is the reference: a fast-forward jumps between rate
  # counter matches and runs the cycles around each step whole.
  describe "#fast_forward" do
    def settle(writes)
      [true, false].map do |stepped|
        chip = described_class.new
        writes.each do |cycles, setter, value|
          stepped ? cycles.times { chip.cycle! } : chip.fast_forward(cycles)
          chip.public_send(setter, value)
        end
        [chip.counter, chip.env3, chip.state]
      end
    end

    it "matches stepping through attack, decay and release" do
      stepped, forwarded = settle([[0, :attack_decay=, 0x11], [0, :sustain_release=, 0x82],
                                   [3, :control=, 0x01], [9000, :control=, 0x00], [30_000, :control=, 0x01],
                                   [17, :control=, 0x00], [5, :attack_decay=, 0x00]])
      expect(forwarded).to eq(stepped)
    end

    it "matches stepping through the ADSR delay bug and a frozen release" do
      stepped, forwarded = settle([[0, :attack_decay=, 0xf0], [0, :control=, 0x01], [1000, :attack_decay=, 0x00],
                                   [40_000, :control=, 0x00], [90_000, :control=, 0x01]])
      expect(forwarded).to eq(stepped)
    end
  end
end
