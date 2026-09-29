# frozen_string_literal: true

require "spec_helper"
require "badline/gui"
require_relative "../../support/drive1541_rom"

describe Badline::GUI::DriveLedPane do
  subject(:pane) { described_class.new(drive, screen) }

  let(:drive) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }
  let(:screen) { Badline::GUI::Pane.new(width: 384, height: 272, left: 0, top: 0) }
  let(:sdl) { Badline::SDL }
  let(:renderer) { Fiddle::Pointer.new(0x2000) }

  # VIA 2's port B: PB3 drives the LED.
  def light(on)
    drive.via2.poke(0x1c02, 0xff)
    drive.via2.poke(0x1c00, on ? 0x08 : 0x00)
  end

  before do
    allow(sdl).to receive(:SDL_SetRenderDrawColor)
    allow(sdl).to receive(:SDL_RenderFillRect)
  end

  it "sits in the bottom right corner of the border" do
    expect([pane.left + pane.width, pane.top + pane.height])
      .to eq([384 - 8, 272 - 6])
  end

  it "is bright while the drive lights the LED" do
    light(true)
    pane.render(renderer)
    expect(sdl).to have_received(:SDL_SetRenderDrawColor).with(renderer, 0xff, 0x20, 0x20, 0xff)
  end

  it "is dim while the LED is off" do
    light(false)
    pane.render(renderer)
    expect(sdl).to have_received(:SDL_SetRenderDrawColor).with(renderer, 0x40, 0x00, 0x00, 0xff)
  end

  it "fills its rectangle" do
    pane.render(renderer)
    expect(sdl).to have_received(:SDL_RenderFillRect).with(renderer, [pane.left, pane.top, 12, 4].pack("l4"))
  end
end
