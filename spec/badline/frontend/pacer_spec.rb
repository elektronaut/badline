# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Pacer do
  subject(:pacer) { described_class.new(paced: true, vsync: true, verbose: false) }

  let(:silent) { instance_double(Badline::Frontend::Sound, playing?: false) }
  let(:playing) { instance_double(Badline::Frontend::Sound, playing?: true, level: 0.04, wait: nil) }

  describe "#cycles" do
    it "clocks the machine's frame without vsync" do
      expect(described_class.new(paced: true, vsync: false, verbose: false).cycles(playing)).to eq(19_656)
    end

    it "clocks a display refresh with vsync" do
      pacer.fit(60)
      expect(pacer.cycles(silent)).to eq(16_420)
    end

    it "steers the audio queue while the sound plays under vsync" do
      pacer.fit(60)
      expect(pacer.cycles(playing)).to be > 16_420
    end
  end

  describe "#wait" do
    it "holds the frame while the sound plays down to the target" do
      described_class.new(paced: true, vsync: false, verbose: false).wait(playing)
      expect(playing).to have_received(:wait).with(Badline::Frontend::Sound::AHEAD)
    end

    it "only holds a frame that would overfill the queue under vsync" do
      pacer.wait(playing)
      expect(playing).to have_received(:wait).with(described_class::SAFETY)
    end

    it "waits out the frame on the timer without vsync or sound" do
      timer = described_class.new(paced: true, vsync: false, verbose: false)
      timer.start(Process.clock_gettime(Process::CLOCK_MONOTONIC))
      expect { timer.wait(silent) }.to change { Process.clock_gettime(Process::CLOCK_MONOTONIC) }.by_at_least(0.019)
    end

    it "doesn't catch up on frames it ran behind on" do
      timer = described_class.new(paced: true, vsync: false, verbose: false)
      timer.start(Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1.0)
      expect { timer.wait(silent) }.to change { Process.clock_gettime(Process::CLOCK_MONOTONIC) }.by_at_most(0.019)
    end
  end

  describe "#check" do
    before { pacer.fit(60) }

    it "keeps vsync while frames come at the display's rate or slower" do
      pacer.check(50, 2.0, 0.0)
      expect(pacer.vsync?).to be(true)
    end

    it "falls back to the timer when frames come far faster than the display" do
      pacer.check(50, 0.2, 0.0)
      expect(pacer.vsync?).to be(false)
    end

    it "says so with verbose" do
      verbose = described_class.new(paced: true, vsync: true, verbose: true)
      expect { verbose.check(50, 0.2, 0.0) }.to output(/Vsync doesn't hold/).to_stdout
    end
  end

  describe "#measure" do
    it "fits the frames to the rate the display presents at" do
      pacer.fit(60)
      pacer.measure(625, 10.0)
      expect(pacer.rate.base_cycles).to eq(15_764)
    end

    it "keeps the display's rate when it runs below it" do
      pacer.fit(60)
      pacer.measure(300, 10.0)
      expect(pacer.rate.base_cycles).to eq(16_420)
    end
  end
end
