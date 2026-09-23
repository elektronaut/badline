# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Waveform::Combined do
  # OSC3 reads the top eight bits. A triangle next to a sawtooth is the
  # phase shifted left, so every table but triangle+pulse's is indexed by the
  # phase; that one is indexed by the triangle, folded at the MSB.
  def osc3(model, selected, phase)
    index = selected == 0x5 ? (phase << 1) & 0xfff : phase
    described_class.tables(model).fetch(selected)[index] >> 4
  end

  it "builds a 4096-entry table for each combination without noise" do
    expect(described_class.tables(:mos6581).transform_values(&:size)).to eq(0x3 => 4096, 0x5 => 4096,
                                                                            0x6 => 4096, 0x7 => 4096)
  end

  # Spot values from SID/resid-test's oscsample dumps, where an AND of the
  # shapers reads otherwise.
  describe "on the 6581" do
    it "raises only the top of a triangle+sawtooth ramp" do
      expect(osc3(:mos6581, 0x3, 0x7ff)).to eq(0x3f)
    end

    it "pulls a triangle+pulse bit down beside a low one" do
      expect(osc3(:mos6581, 0x5, 0x7f8)).to eq(0xfc)
    end

    it "grounds a sawtooth+pulse the low bits hold down" do
      expect(osc3(:mos6581, 0x6, 0x7f0)).to eq(0x00)
    end
  end

  describe "on the 8580" do
    it "raises more of a triangle+sawtooth ramp" do
      expect(osc3(:mos8580, 0x3, 0x7f6)).to eq(0x3e)
    end

    it "clears the sawtooth+pulse bits below the top ones" do
      expect(osc3(:mos8580, 0x6, 0x7d7)).to eq(0x7c)
    end
  end

  describe Badline::SID::Waveform::Combined::Network do
    # No neighbours, no pulse: a lone line reads its own drive.
    subject(:network) { described_class.new([1.0, 0.0, 0.5] + Array.new(22, 0.0)) }

    it "reads a single drive straight through" do
      expect(network.shape([[0xa5a, 1.0]], false)).to eq(0xa5a)
    end

    it "reads a line high once half its drive is, at a threshold of a half" do
      expect(network.shape([[0xff0, 1.0], [0x0ff, 1.0]], false)).to eq(0xfff)
    end
  end
end
