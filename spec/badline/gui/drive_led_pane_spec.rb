# frozen_string_literal: true

require "spec_helper"
require "badline/gui"
require_relative "../../support/drive1541_rom"

describe Badline::GUI::DriveLedPane do
  subject(:pane) { described_class.new(drive) }

  let(:drive) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }
  let(:sdl) { Badline::SDL }
  let(:renderer) { Fiddle::Pointer.new(0x2000) }

  # VIA 2's port B: PB3 drives the LED.
  def light(on)
    drive.via2.poke(0x1c02, 0xff)
    drive.via2.poke(0x1c00, on ? 0x08 : 0x00)
  end

  before do
    allow(sdl::SetRenderDrawColor).to receive(:call)
    allow(sdl::RenderFillRect).to receive(:call)
  end

  it "sits in the bottom right corner of the border" do
    expect([pane.left + pane.width, pane.top + pane.height])
      .to eq([Badline::GUI::ScreenPane::WIDTH - 8, Badline::GUI::ScreenPane::HEIGHT - 6])
  end

  it "is bright while the drive lights the LED" do
    light(true)
    pane.render(renderer)
    expect(sdl::SetRenderDrawColor).to have_received(:call).with(renderer, 0xff, 0x20, 0x20, 0xff)
  end

  it "is dim while the LED is off" do
    light(false)
    pane.render(renderer)
    expect(sdl::SetRenderDrawColor).to have_received(:call).with(renderer, 0x40, 0x00, 0x00, 0xff)
  end

  it "fills its rectangle" do
    pane.render(renderer)
    expect(sdl::RenderFillRect).to have_received(:call).with(renderer, [pane.left, pane.top, 12, 4].pack("l4"))
  end
end
