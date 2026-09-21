# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Filter do
  subject(:filter) { described_class.new }

  # Voices reach the filter as 20-bit samples and are scaled down by 7 bits,
  # so $8000 arrives as 256.
  let(:voices) { Array.new(3) { Struct.new(:output).new(0x8000) } }

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

  describe "cutoff curve" do
    it "covers the whole 11-bit range" do
      expect(described_class::W0.length).to eq(2048)
    end

    it "rises with the register value" do
      expect(described_class::W0.each_cons(2)).to all(satisfy { |low, high| high >= low })
    end

    it "stays below the rate the integrator can follow" do
      expect(described_class::W0.max).to be <= described_class::W0_MAX
    end
  end

  describe "the unfiltered mix" do
    before { filter.write(0x18, 0x0f) }

    it "sums the voices around the mixer offset" do
      filter.cycle!(voices)
      expect(filter.output).to eq(((256 * 3) + described_class::MIXER_DC) * 0x0f)
    end

    it "scales by the master volume" do
      filter.write(0x18, 0x01)
      filter.cycle!(voices)
      expect(filter.output).to eq((256 * 3) + described_class::MIXER_DC)
    end

    it "is silent at volume zero" do
      filter.write(0x18, 0x00)
      filter.cycle!(voices)
      expect(filter.output).to eq(0)
    end

    it "drops a voice routed into the filter" do
      filter.write(0x17, 0x01)
      filter.cycle!(voices)
      expect(filter.output).to eq(((256 * 2) + described_class::MIXER_DC) * 0x0f)
    end

    it "drops voice 3 when MODE/VOL bit 7 is set" do
      filter.write(0x18, 0x8f)
      filter.cycle!(voices)
      expect(filter.output).to eq(((256 * 2) + described_class::MIXER_DC) * 0x0f)
    end

    # Bit 7 cuts the bypass path, not the filter input.
    it "keeps voice 3 when it is routed through the filter" do
      filter.write(0x17, 0x04)
      filter.write(0x18, 0x9f)
      filter.cycle!(voices)
      expect(filter.output).to eq(((256 * 2) + described_class::MIXER_DC) * 0x0f)
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

    it "integrates the high-pass into the band-pass" do
      run(2)
      expect(filter.bandpass).to eq(14)
    end

    it "leaves the band-pass to charge before the low-pass follows" do
      run(2)
      expect(filter.lowpass).to eq(0)
    end

    # Truncation in the fixed-point integrators leaves the settled state a
    # few LSBs short of the analytic one.
    it "settles the low-pass onto the inverted input" do
      run(10_000)
      expect(filter.lowpass).to be_within(24).of(-256)
    end

    it "leaves the high-pass at rest once it settles" do
      run(10_000)
      expect(filter.highpass.abs).to be < 24
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

    it "overshoots further at full resonance" do
      expect(peak_bandpass(0xf1)).to eq(187)
    end

    it "overshoots least at zero resonance" do
      expect(peak_bandpass(0x01)).to eq(125)
    end
  end
end
