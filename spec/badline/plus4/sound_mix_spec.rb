# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4::SoundMix do
  subject(:mix) { described_class.new(ted_sound, sid) }

  let(:ted_sound) { instance_double(Badline::Chips::TED::Sound, record: nil, drain_samples: [], catch_up!: nil) }
  let(:sid) { Badline::Chips::SID.new(at: 0xfd40) }

  def drain(ted, sid_samples)
    allow(ted_sound).to receive(:drain_samples).and_return(ted)
    allow(sid).to receive(:drain_samples).and_return(sid_samples)
    mix.drain_samples
  end

  it "adds the two sources' samples" do
    expect(drain([100, -200], [30, 40])).to eq([130, -160])
  end

  it "clips the sum to a signed 16-bit sample" do
    expect(drain([30_000, -30_000], [10_000, -10_000])).to eq([32_767, -32_768])
  end

  it "keeps a sample one source closed until the other closes it" do
    drain([1, 2, 3], [10])
    expect(drain([], [20, 30])).to eq([22, 33])
  end

  it "records both sources at the rate asked" do
    mix.record(rate: 22_050, clock_hz: 886_724)
    expect(ted_sound).to have_received(:record).with(rate: 22_050, clock_hz: 886_724)
  end

  it "names and swaps the SID's model" do
    mix.model = :mos8580
    expect([mix.model, sid.model]).to eq(%i[mos8580 mos8580])
  end
end
