# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/sdl_dummy_drivers"

describe Badline::Frontend::Sound do
  include_context "with SDL's dummy drivers"

  def spied_sid = Badline::SID.new.tap { |sid| allow(sid).to receive(:record) }

  def opened(sid, clock_hz) = described_class.new(sid, clock_hz, true, false).tap { |sound| sounds << sound }

  let(:sounds) { [] }

  after { sounds.each(&:close) }

  it "records the SID at the machine's clock" do
    sid = spied_sid
    sound = opened(sid, Badline::Region::NTSC.clock_hz)
    expect(sid).to have_received(:record).with(rate: sound.rate, clock_hz: 1_022_727)
  end

  it "records another machine's SID at that machine's clock" do
    sound = opened(spied_sid, Badline::Region::PAL.clock_hz)
    sid = spied_sid
    sound.switch(sid, Badline::Region::NTSC.clock_hz)
    expect(sid).to have_received(:record).with(rate: sound.rate, clock_hz: 1_022_727)
  end
end
