# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/crtc_recorder"

describe Badline::Chips::CRTC::KeyedState do
  include KeyedOracle

  # A small frame with vertical adjust, as the CRTC spec's: lines of 10
  # characters, rows of 2 lines, 4 rows and a line of adjust.
  let(:small) { [9, 4, 6, 0x0f, 3, 1, 2, 3, 0, 1, 0, 0, 0x10, 0x00] }

  def crtc_at(cycles, output = CRTCRecorder.new)
    Badline::Chips::CRTC.new(output).tap do |crtc|
      small.each_with_index do |value, register|
        crtc.poke(0, register)
        crtc.poke(1, value)
      end
      cycles.times { crtc.cycle! }
    end
  end

  def restored(crtc, output = CRTCRecorder.new)
    Badline::Chips::CRTC.new(output).tap { |fresh| keyed_round_trip(crtc, fresh) }
  end

  # The characters the CRTC hands `output` over the next 100 cycles.
  def shown(crtc, output)
    output.clear
    100.times { crtc.cycle! }
    output.characters
  end

  it "saves again the fields it loaded, on every cycle of a frame" do
    differing = (0..95).reject { |cycles| saved_fields(restored(crtc_at(cycles))) == saved_fields(crtc_at(cycles)) }
    expect(differing).to be_empty
  end

  it "shows the characters the saved CRTC does, from the vertical adjust on" do
    ours = CRTCRecorder.new
    theirs = CRTCRecorder.new
    crtc = crtc_at(83, ours)
    expect(shown(restored(crtc, theirs), theirs)).to eq(shown(crtc, ours))
  end

  it "reads back the register selected" do
    crtc = crtc_at(5).tap do |chip|
      chip.poke(0, 14)
      chip.poke(1, 0x2a)
    end
    expect(restored(crtc).peek(1)).to eq(0x2a)
  end
end
