# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/fake_sink"

describe Badline::Audio::Stream do
  subject(:stream) do
    described_class.new(sink, sid, ahead: 0.1, limit: 0.25, on_underrun: -> { underruns << true })
  end

  let(:sink) { FakeSink.new(rate: 1000) }
  let(:sid) { instance_double(Badline::SID, record: nil) }
  let(:underruns) { [] }

  before { allow(sid).to receive(:drain_samples) { Array.new(20, 0) } }

  # Each frame renders 20 samples, 20 ms at the sink's rate, and the device
  # plays `speed` frames' worth while the next one renders.
  def run(frames, speed: 1.0)
    frames.times do
      stream.feed
      sink.advance(0.02 / speed)
    end
  end

  it "records the SID at the device's rate" do
    stream
    expect(sid).to have_received(:record).with(rate: 1000)
  end

  describe "#feed" do
    it "queues what the SID recorded" do
      stream.feed
      expect(sink.queued).to eq(20)
    end

    it "holds the device until the queue reaches the lead" do
      4.times { stream.feed }
      expect(sink.started?).to be(false)
    end

    it "starts the device once the queue reaches the lead" do
      5.times { stream.feed }
      expect(sink.started_with).to eq(100)
    end

    it "keeps the lead, less the frame playing, at real time" do
      run(500)
      expect(sink.queued).to eq(80)
    end

    it "plays every sample at real time" do
      run(500)
      expect(sink.played + sink.queued).to eq(10_000)
    end

    it "keeps up at real time" do
      run(500)
      expect(underruns).to be_empty
    end
  end

  describe "above real time" do
    it "keeps the queue within the limit" do
      run(500, speed: 3.0)
      expect(sink.peak).to be <= 250
    end

    it "drops the frames that don't fit" do
      run(500, speed: 3.0)
      expect(stream.dropped).to be_positive
    end

    it "drops whole frames" do
      run(500, speed: 3.0)
      expect(sink.played + sink.queued + stream.dropped).to eq(10_000)
    end
  end

  describe "below real time" do
    it "says so once" do
      run(100, speed: 0.5)
      expect(underruns.size).to eq(1)
    end

    it "counts every time the queue runs dry" do
      run(100, speed: 0.5)
      expect(stream.underruns).to be > 1
    end

    it "stops the device when the queue runs dry" do
      run(10, speed: 0.5)
      stream.feed
      expect(sink.running?).to be(false)
    end

    it "restarts once the lead is back" do
      run(100, speed: 0.5)
      expect(sink.played).to be > 800
    end
  end

  describe "#toggle_mute" do
    it "mutes" do
      stream.toggle_mute
      expect(stream.muted?).to be(true)
    end

    it "drops the queue" do
      3.times { stream.feed }
      stream.toggle_mute
      expect(sink.queued).to eq(0)
    end

    it "stops the device" do
      run(10)
      stream.toggle_mute
      expect(sink.running?).to be(false)
    end

    it "queues nothing while muted" do
      stream.toggle_mute
      run(10)
      expect(sink.queued).to eq(0)
    end

    it "keeps draining the SID while muted" do
      stream.toggle_mute
      run(10)
      expect(sid).to have_received(:drain_samples).exactly(10).times
    end

    it "fills the lead again before the device restarts" do
      run(10)
      stream.toggle_mute
      stream.toggle_mute
      4.times { stream.feed }
      expect(sink.running?).to be(false)
    end
  end

  describe "#pace" do
    let(:clock) { FakeClock.new(sink) }

    before { stream.clock = clock }

    # Each frame renders 20 ms of samples in `cost` seconds, then paces;
    # the frames are `period` seconds apart when the clock paces them.
    def paced(frames, cost: 0.005, period: 0.02)
      frames.times do
        stream.feed
        clock.pass(cost)
        stream.pace(period)
      end
    end

    it "waits a frame on the clock while the queue fills" do
      stream.feed
      stream.pace(0.02)
      stream.pace(0.02)
      expect(clock.now).to eq(0.02)
    end

    it "doesn't wait on the clock for a frame that ran late" do
      stream.pace(0.02)
      clock.pass(0.05)
      stream.pace(0.02)
      expect(clock.slept).to eq(0.0)
    end

    it "waits for the device to play the queue down to the lead" do
      paced(10)
      expect(sink.queued).to be <= 100
    end

    it "keeps the lead once the device plays" do
      paced(3000)
      expect(sink.queued).to be >= 100 - 20
    end

    it "never runs dry above real time, however long the frames' period" do
      paced(3000, period: 0.0202)
      expect(stream.underruns).to eq(0)
    end

    it "drops nothing above real time" do
      paced(3000)
      expect(stream.dropped).to eq(0)
    end

    it "runs the machine at the device's rate" do
      paced(3000)
      expect(clock.now).to be_within(0.2).of(60.0)
    end

    it "paces by the clock while muted" do
      paced(10)
      stream.toggle_mute
      paced(1)
      expect { paced(10) }.to change(clock, :now).by(be_within(0.001).of(0.2))
    end
  end

  it "closes the device" do
    stream.close
    expect(sink.closed?).to be(true)
  end
end
