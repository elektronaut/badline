# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Screens do
  subject(:screens) { described_class.new(computer) }

  let(:computer) { Badline::C128.new(mode: :c128) }

  # Sets the screen editor's 40/80 flag in +machine+ and calls #follow
  # once a frame for +frames+ frames.
  def follow(vdc, frames = described_class::FOLLOW_FRAMES, machine: computer)
    machine.ram.poke(0xd7, vdc ? 0x80 : 0)
    frames.times { screens.follow }
  end

  it "switches to the VDC once the C128 has printed there for FOLLOW_FRAMES frames" do
    follow(true)
    expect(screens.vdc_shown?).to be(true)
  end

  it "goes stale once it switches, for #build to build the VDC's screen" do
    follow(true)
    expect(screens.stale?).to be(true)
  end

  it "is fresh again once #build builds the VDC's screen" do
    follow(true)
    screens.build
    expect(screens.stale?).to be(false)
  end

  it "waits out a move that doesn't last, as the KERNAL's reset makes" do
    follow(true, described_class::FOLLOW_FRAMES - 1)
    follow(false)
    expect(screens.vdc_shown?).to be(false)
  end

  it "renders the VDC in place of the VIC-IIe once it switches" do
    follow(true)
    expect([computer.vdc.render, computer.vic.render?]).to eq([true, false])
  end

  it "switches back to the VIC-IIe once the C128 prints there again" do
    follow(true)
    follow(false)
    expect(screens.vdc_shown?).to be(false)
  end

  it "keeps the screen #show_vdc picked while the C128 stays put" do
    follow(true)
    screens.show_vdc(false)
    follow(true)
    expect(screens.vdc_shown?).to be(false)
  end

  it "follows the C128's next move after #show_vdc" do
    screens.show_vdc(true)
    follow(true)
    follow(false)
    expect(screens.vdc_shown?).to be(false)
  end

  it "takes up a move to the screen #show_vdc already shows" do
    screens.show_vdc(true)
    follow(true)
    screens.show_vdc(false)
    follow(true)
    expect(screens.vdc_shown?).to be(false)
  end

  it "follows another machine from its VIC-IIe" do
    other = Badline::C128.new(mode: :c128)
    follow(true)
    screens.computer = other
    follow(true, machine: other)
    expect(screens.vdc_shown?).to be(true)
  end

  context "with a C64" do
    let(:computer) { Badline::Computer.new }

    it "stays on the VIC-II" do
      screens.follow
      expect(screens.vdc_shown?).to be(false)
    end
  end
end
