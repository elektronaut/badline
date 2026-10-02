# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::SIDHistory do
  subject(:history) { described_class.new(1000) }

  let(:sid) { Badline::SID.new }

  # Records a frame that ends at `rendered` seconds with the first voice's
  # frequency low byte set to `marker`.
  def frame(rendered, marker, samples = [])
    sid.poke(0xd400, marker)
    history.record(sid, samples, rendered)
  end

  it "shows the frame being heard rather than the last one rendered" do
    [0.02, 0.04, 0.06].each_with_index { |rendered, marker| frame(rendered, marker + 1) }
    expect(history.register(history.frame(0.045), 0)).to eq(2)
  end

  it "shows the oldest frame kept before any was heard" do
    frame(0.02, 7)
    frame(0.04, 8)
    expect(history.register(history.frame(0.0), 0)).to eq(7)
  end

  it "keeps each voice's envelope" do
    sid.poke(0xd405, 0x00)
    sid.poke(0xd404, 0x11)
    5_000.times { sid.cycle! }
    frame(0.02, 0)
    expect(history.state(history.frame(0.02), 0)).to eq(:decay_sustain)
  end

  it "starts the scope where the wave rises through its middle" do
    frame(0.1, 0, Array.new(100) { |index| (index % 20) < 10 ? -100 : 100 })
    expect(history.scope_start(0.1, 30) % 20).to eq(10)
  end

  it "reads back the samples heard" do
    frame(0.1, 0, (1..100).to_a)
    expect(history.sample_at(history.scope_start(0.1, 100))).to eq(1)
  end

  context "when the SID records its voices" do
    before do
      sid.record(rate: 1000)
      sid.record_voices!
      sid.poke(0xd404, 0x09)
      5_000.times { sid.cycle! }
    end

    it "keeps each voice's output beside the mix" do
      history.record(sid, sid.drain_samples, 0.005)
      expect(history.sample_at(0, 0)).not_to eq(history.sample_at(0, 1))
    end
  end
end
