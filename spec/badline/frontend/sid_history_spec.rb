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
    history.record([sid], [samples], samples.flat_map { |sample| [sample, sample] }, rendered)
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
      samples = sid.drain_samples
      history.record([sid], [samples], samples + samples, 0.005)
      expect(history.sample_at(0, 0)).not_to eq(history.sample_at(0, 1))
    end
  end

  context "with two SIDs" do
    subject(:history) { described_class.new(1000, 2) }

    let(:second) { Badline::SID.new(at: 0xd420) }

    before do
      sid.poke(0xd400, 1)
      second.poke(0xd420, 2)
      history.record([sid, second], [[10, 11], [20, 21]], [-1, 1, -2, 2], 0.1)
    end

    it "keeps each SID's registers" do
      expect(history.register(history.frame(0.1, 1), 0)).to eq(2)
    end

    it "keeps each SID's own output" do
      expect(history.sample_at(1, history.output(1))).to eq(21)
    end

    it "keeps the left of the mix" do
      expect(history.sample_at(1, history.left)).to eq(-2)
    end

    it "keeps the right of the mix" do
      expect(history.sample_at(1, history.right)).to eq(2)
    end
  end
end
