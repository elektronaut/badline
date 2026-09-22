# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Filter do
  subject(:filter) { described_class.new }

  # Voices reach the filter as 20-bit samples and are scaled down by 7 bits,
  # so $8000 arrives as 256.
  let(:voices) { Array.new(3) { Struct.new(:output).new(0x8000) } }
  let(:silent_voices) { Array.new(3) { Struct.new(:output).new(0) } }

  def cutoff_hz(model, register)
    (described_class::W0[model][register] / (2 * Math::PI * described_class::SCALE)).round
  end

  describe "register decoding" do
    it "takes the low three bits of the cutoff from $D415" do
      filter.write(0x15, 0xff)
      expect(filter.cutoff).to eq(0x007)
    end

    it "takes the high eight bits of the cutoff from $D416" do
      filter.write(0x16, 0xff)
      expect(filter.cutoff).to eq(0x7f8)
    end

    it "takes the routing from the low nibble of $D417" do
      filter.write(0x17, 0xf5)
      expect(filter.routing).to eq(0x5)
    end

    it "takes the mode from bits 4-6 of $D418" do
      filter.write(0x18, 0xff)
      expect(filter.mode).to eq(0x7)
    end

    it "takes the volume from the low nibble of $D418" do
      filter.write(0x18, 0xff)
      expect(filter.volume).to eq(0xf)
    end

    it "silences voice 3 on bit 7 of $D418" do
      filter.write(0x18, 0x80)
      expect(filter).to be_voice3_off
    end
  end

  describe "the 6581 cutoff curve" do
    it "covers the whole 11-bit range" do
      expect(described_class::W0[:mos6581].length).to eq(2048)
    end

    it "rises with the register value" do
      expect(described_class::W0[:mos6581].each_cons(2)).to all(satisfy { |low, high| high >= low })
    end

    it "stays below the rate the integrator can follow" do
      expect(described_class::W0[:mos6581].max).to be <= described_class::W0_MAX
    end

    it "bottoms out at 220 Hz" do
      expect(cutoff_hz(:mos6581, 0x000)).to eq(220)
    end

    it "tops out at 8.6 kHz" do
      expect(cutoff_hz(:mos6581, 0x7ff)).to eq(8600)
    end
  end

  describe "the 8580 cutoff curve" do
    it "covers the whole 11-bit range" do
      expect(described_class::W0[:mos8580].length).to eq(2048)
    end

    it "rises with the register value" do
      expect(described_class::W0[:mos8580].each_cons(2)).to all(satisfy { |low, high| high >= low })
    end

    it "starts from zero rather than the 6581's floor" do
      expect(cutoff_hz(:mos8580, 0x000)).to eq(0)
    end

    it "tops out at 12.5 kHz" do
      expect(cutoff_hz(:mos8580, 0x7ff)).to eq(12_500)
    end

    # The 8580 climbs in a near-straight line where the 6581 spends its
    # lower half barely off the floor.
    it "is already at 3.3 kHz a quarter of the way up" do
      expect(cutoff_hz(:mos8580, 0x200)).to eq(3300)
    end

    it "leaves the 6581 at 420 Hz there" do
      expect(cutoff_hz(:mos6581, 0x200)).to eq(420)
    end
  end

  describe "the chip model" do
    it "defaults to the 6581" do
      expect(filter.model).to eq(:mos6581)
    end

    it "rejects a model it has no curve for" do
      expect { described_class.new(model: :mos6582) }.to raise_error(KeyError)
    end

    it "sits the 6581's silent mix on the mixer offset" do
      filter.write(0x18, 0x0f)
      filter.cycle!(silent_voices)
      expect(filter.mix).to eq(described_class::MIXER_DC[:mos6581] * 0x0f)
    end

    context "with an 8580" do
      subject(:filter) { described_class.new(model: :mos8580) }

      it "has no mixer offset to sit on" do
        filter.write(0x18, 0x0f)
        filter.cycle!(silent_voices)
        expect(filter.mix).to eq(0)
      end
    end
  end

  describe "the unfiltered mix" do
    before { filter.write(0x18, 0x0f) }

    it "sums the voices around the mixer offset" do
      filter.cycle!(voices)
      expect(filter.mix).to eq(((256 * 3) + described_class::MIXER_DC[:mos6581]) * 0x0f)
    end

    it "scales by the master volume" do
      filter.write(0x18, 0x01)
      filter.cycle!(voices)
      expect(filter.mix).to eq((256 * 3) + described_class::MIXER_DC[:mos6581])
    end

    it "is silent at volume zero" do
      filter.write(0x18, 0x00)
      filter.cycle!(voices)
      expect(filter.mix).to eq(0)
    end

    it "drops a voice routed into the filter" do
      filter.write(0x17, 0x01)
      filter.cycle!(voices)
      expect(filter.mix).to eq(((256 * 2) + described_class::MIXER_DC[:mos6581]) * 0x0f)
    end

    it "drops voice 3 when MODE/VOL bit 7 is set" do
      filter.write(0x18, 0x8f)
      filter.cycle!(voices)
      expect(filter.mix).to eq(((256 * 2) + described_class::MIXER_DC[:mos6581]) * 0x0f)
    end

    # Bit 7 cuts the bypass path, not the filter input.
    it "keeps voice 3 when it is routed through the filter" do
      filter.write(0x17, 0x04)
      filter.write(0x18, 0x9f)
      filter.cycle!(voices)
      expect(filter.mix).to eq(((256 * 2) + described_class::MIXER_DC[:mos6581]) * 0x0f)
    end
  end

  describe "state variable integrator" do
    before do
      filter.write(0x16, 0xff) # cutoff wide open
      filter.write(0x17, 0x01) # voice 1 into the filter
      filter.write(0x18, 0x1f) # low-pass, full volume
    end

    def run(cycles)
      cycles.times { filter.cycle!(voices) }
    end

    it "inverts the input into the high-pass on the first cycle" do
      run(1)
      expect(filter.highpass).to eq(-256)
    end

    # 13.8 in floating point, read out in whole units.
    it "integrates the high-pass into the band-pass" do
      run(2)
      expect(filter.bandpass).to eq(13)
    end

    # -0.74 in floating point, which whole-unit integrators round to zero.
    it "moves the low-pass by a fraction of a unit behind the band-pass" do
      run(2)
      expect(filter.lowpass).to eq(-1)
    end

    it "settles the low-pass onto the inverted input" do
      run(10_000)
      expect(filter.lowpass).to be_within(1).of(-256)
    end

    it "leaves the high-pass at rest once it settles" do
      run(10_000)
      expect(filter.highpass.abs).to be <= 1
    end
  end

  describe "resonance" do
    before do
      filter.write(0x16, 0xff)
      filter.write(0x18, 0x2f) # band-pass, full volume
    end

    # Resonance shapes the transient rather than the settled state, so the
    # band-pass overshoot on a step input measures it.
    def peak_bandpass(res_filt)
      filter.write(0x17, res_filt)
      400.times.map do
        filter.cycle!(voices)
        filter.bandpass.abs
      end.max
    end

    # 174.3 and 117.8 in floating point.
    it "overshoots further at full resonance" do
      expect(peak_bandpass(0xf1)).to eq(174)
    end

    it "overshoots least at zero resonance" do
      expect(peak_bandpass(0x01)).to eq(117)
    end
  end

  describe "the board's RC network" do
    subject(:external) { described_class::External.new }

    def run(input, cycles)
      cycles.times { external.cycle!(input) }
      external.output
    end

    it "starts at rest" do
      expect(run(100_000, 1)).to eq(0)
    end

    # 10kΩ/1000pF puts one time constant at 10 cycles of a 1 MHz clock.
    it "charges to about 63% of a step in one time constant" do
      expect(run(100_000, 11)).to be_within(3000).of(63_000)
    end

    it "settles onto the step" do
      expect(run(100_000, 50)).to be_within(1000).of(100_000)
    end

    # 1kΩ/10µF puts the high-pass corner at ~16 Hz, a 10 ms time constant.
    it "decays a steady level over its time constant" do
      expect(run(176_790, 10_000)).to be_within(10_000).of(176_790 / Math::E)
    end

    # In whole units the high-pass step rounds down to zero on any gap
    # under 2^20/105, so reSID's stalls ~10k short. This one keeps decaying.
    it "keeps decaying where a whole-unit integrator stalls" do
      expect(run(176_790, 50_000)).to be_within(3).of(176_790 * Math.exp(-50_000 * 105 / (2.0**20)))
    end
  end

  describe "the output path" do
    before { filter.write(0x18, 0x0f) }

    it "is silent while the RC network charges" do
      filter.cycle!(voices)
      expect(filter.output).to eq(0)
    end

    # The high-pass has drained about 1% of it by then.
    it "settles onto the mix" do
      100.times { filter.cycle!(voices) }
      expect(filter.output).to be_within(filter.mix / 100).of(filter.mix)
    end
  end
end
