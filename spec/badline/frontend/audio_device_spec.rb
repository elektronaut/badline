# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/sdl_dummy_drivers"

describe Badline::Frontend::AudioDevice do
  include_context "with SDL's dummy drivers"

  def device(channels) = described_class.new(channels:, rate: 8000, samples: 512).tap { |dev| devices << dev }

  def opened(channels) = device(channels).tap { |dev| dev.open(true) }

  let(:devices) { [] }

  after { devices.each(&:close) }

  it "is closed until opened" do
    expect(device(1)).not_to be_open
  end

  it "opens at the rate asked for when it must be exact" do
    expect(opened(1).rate).to eq(8000)
  end

  it "counts a mono queue in single samples" do
    mono = opened(1)
    mono.queue([0] * 800)
    expect(mono.queued_seconds).to be_within(0.005).of(0.1)
  end

  it "counts a stereo queue in sample pairs" do
    stereo = opened(2)
    stereo.queue([0] * 1600)
    expect(stereo.queued_seconds).to be_within(0.005).of(0.1)
  end

  it "drops the queue on a clear" do
    mono = opened(1)
    mono.queue([0] * 800)
    mono.clear
    expect(mono.queued_seconds).to eq(0.0)
  end

  it "is closed after a close" do
    mono = opened(1)
    mono.close
    expect(mono).not_to be_open
  end

  context "when SDL has no such driver" do
    before { ENV["SDL_AUDIODRIVER"] = "no-such-driver" }

    it "stays closed" do
      mono = device(1)
      mono.open(false)
      expect(mono).not_to be_open
    end
  end
end
