# frozen_string_literal: true

require "spec_helper"

describe Badline::Audio::SDLSink do
  around do |example|
    driver = ENV.fetch("SDL_AUDIODRIVER", nil)
    ENV["SDL_AUDIODRIVER"] = "dummy"
    example.run
  ensure
    ENV["SDL_AUDIODRIVER"] = driver
  end

  describe "an open device" do
    subject(:sink) { described_class.new(rate: 8000, exact_rate: true) }

    after { sink.close }

    it "runs at the rate asked for" do
      expect(sink.rate).to eq(8000)
    end

    it "holds queued samples until it starts" do
      sink.queue([0] * 800)
      expect(sink.queued_seconds).to be_within(0.005).of(0.1)
    end

    it "drops the queue on a clear" do
      sink.queue([0] * 800)
      sink.clear
      expect(sink.queued_seconds).to eq(0.0)
    end

    it "plays the queue out once started" do
      sink.queue([0] * 80)
      sink.start
      sleep 0.01 until sink.queued_seconds.zero?
      expect(sink.queued_seconds).to eq(0.0)
    end

    it "closes only once" do
      sink.close
      expect { sink.close }.not_to raise_error
    end
  end

  context "when SDL has no such driver" do
    before { ENV["SDL_AUDIODRIVER"] = "no-such-driver" }

    it "raises with SDL's reason" do
      expect { described_class.new(rate: 8000) }.to raise_error(described_class::Error, /no-such-driver/)
    end
  end
end
