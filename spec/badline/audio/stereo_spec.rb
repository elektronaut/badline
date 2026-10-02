# frozen_string_literal: true

require "spec_helper"

describe Badline::Audio::Stereo do
  subject(:stereo) { described_class.new(bus, tune, %i[mos6581 mos8580 mos6581]) }

  let(:bus) { Badline::AddressBus.new }
  let(:tune) { instance_double(Badline::Storage::SIDFile, sid_addresses: addresses) }
  let(:addresses) { [] }

  # Has each SID give up the samples in `outputs`, then mixes them.
  def mix(*outputs)
    stereo.sids.each_with_index { |sid, index| allow(sid).to receive(:drain_samples).and_return(outputs[index]) }
    mixed = []
    stereo.mix { |sample| mixed << sample }
    mixed
  end

  it "plays the bus's own SID alone" do
    expect(stereo.sids).to eq([bus.sid])
  end

  it "plays one SID on both channels" do
    expect(mix([100, -200])).to eq([100, 100, -200, -200])
  end

  it "keeps each SID's own samples" do
    mix([100, -200])
    expect(stereo.outputs).to eq([[100, -200]])
  end

  context "with a second SID" do
    let(:addresses) { [0xd420] }

    it "fits it at the address the tune gives" do
      expect(stereo.sids.last.start).to eq(0xd420)
    end

    it "fits it with its own model" do
      expect(stereo.sids.map(&:model)).to eq(%i[mos6581 mos8580])
    end

    it "puts it on the bus" do
      second = stereo.sids.last
      bus.poke(0xd438, 0x0f)
      expect(second.register(0x18)).to eq(0x0f)
    end

    it "refits every SID with a model" do
      stereo.refit(:mos6581)
      expect(stereo.models).to eq(%i[mos6581 mos6581])
    end

    it "refits each SID with its own model on auto" do
      stereo.refit(:mos6581)
      stereo.refit(:auto)
      expect(stereo.models).to eq(%i[mos6581 mos8580])
    end

    it "plays the first SID on the left and the second on the right" do
      expect(mix([100, -200], [300, 400])).to eq([100, 300, -200, 400])
    end
  end

  context "with a third SID" do
    let(:addresses) { [0xd420, 0xd500] }

    it "plays it in the centre, at half on each side" do
      expect(mix([300], [-300], [600])).to eq([400, 0])
    end

    it "keeps the mix within 16 bits" do
      expect(mix([32_767], [-32_768], [32_767])).to eq([32_767, -10_923])
    end
  end
end
