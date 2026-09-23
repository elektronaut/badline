# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/fake_sink"

describe Badline::Audio::Playback do
  subject(:playback) do
    described_class.new(sink, sleeper: ->(seconds) { sleeper.call(seconds) }, on_underrun: -> { underruns << true })
  end

  let(:sink) { FakeSink.new(rate: 1000) }
  let(:renderer) { FakeRenderer.new(sink, frames: 50, size: 20) }
  let(:sleeper) { ->(seconds) { sink.advance(seconds) } }
  let(:underruns) { [] }

  describe "#play" do
    it "queues every sample" do
      playback.play(renderer)
      expect(sink.total_seconds).to eq(1.0)
    end

    it "plays every sample before it returns" do
      playback.play(renderer)
      expect(sink.played).to eq(1000)
    end

    it "keeps no more than a frame past the lead queued" do
      playback.play(renderer)
      expect(sink.peak).to be <= 150 + 20
    end

    it "starts the device once the queue reaches the lead" do
      playback.play(renderer)
      expect(sink.started_with).to eq(160)
    end

    it "closes the device once the queue has drained" do
      playback.play(renderer)
      expect(sink.closed_with).to eq(0)
    end

    it "finishes" do
      expect(playback.play(renderer)).to eq(:finished)
    end

    it "keeps up with a renderer faster than real time" do
      playback.play(renderer)
      expect(underruns).to be_empty
    end

    it "yields the seconds played, a lead behind those rendered" do
      played = []
      playback.play(renderer) { |seconds| played << seconds }
      expect(played.last).to be_between(1.0 - 0.15 - 0.02, 1.0 - 0.15)
    end

    context "with a tune shorter than the lead" do
      let(:renderer) { FakeRenderer.new(sink, frames: 3, size: 20) }

      it "starts the device at the end and plays it all" do
        playback.play(renderer)
        expect([sink.started_with, sink.played]).to eq([60, 60])
      end
    end

    context "with a renderer slower than real time" do
      let(:renderer) { FakeRenderer.new(sink, frames: 50, size: 20, cost: 0.04) }

      it "reports the underrun once" do
        playback.play(renderer)
        expect(underruns.length).to eq(1)
      end

      it "still plays every sample" do
        playback.play(renderer)
        expect(sink.played).to eq(1000)
      end

      it "says it fell behind" do
        playback.play(renderer)
        expect(playback.underrun?).to be(true)
      end
    end

    context "when stopped" do
      def play = playback.play(renderer) { |seconds| playback.stop if seconds >= 0.3 }

      it "reports the stop" do
        expect(play).to eq(:stopped)
      end

      it "renders no further" do
        play
        expect(renderer.rendered).to be < 50
      end

      it "drops the queue rather than playing it out" do
        play
        expect(sink.cleared).to be(true)
      end

      it "closes the device" do
        play
        expect(sink.closed?).to be(true)
      end
    end

    context "when interrupted" do
      let(:sleeper) { ->(_seconds) { raise Interrupt } }

      it "reports the interrupt" do
        expect(playback.play(renderer)).to eq(:interrupted)
      end

      it "drops the queue and closes the device" do
        playback.play(renderer)
        expect([sink.cleared, sink.closed_with]).to eq([true, 0])
      end
    end

    context "with the SID behind it" do
      let(:tune_path) { File.join(Dir.mktmpdir, "tune.sid") }
      let(:renderer) do
        Badline::Audio::Renderer.new(Badline::Storage::SIDFile.new(tune_path), seconds: 0.5, rate: 8000)
      end
      let(:sink) { FakeSink.new(rate: 8000) }

      before do
        require_relative "../../support/tiny_sid"
        File.binwrite(tune_path, TinySID.bytes)
      end

      after { FileUtils.remove_entry(File.dirname(tune_path)) }

      it "plays exactly the length asked for" do
        playback.play(renderer)
        expect(sink.played).to eq(4000)
      end
    end
  end
end
