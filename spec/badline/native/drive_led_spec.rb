# frozen_string_literal: true

require "spec_helper"
require_relative "../../../native/lib/badline/native/screen"
require_relative "../../../native/lib/badline/native/drive_led"
require_relative "../../support/drive1541_rom"

describe Badline::Native::DriveLed do
  subject(:led) { described_class.new(drive) }

  let(:drive) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }

  # VIA 2's port B: PB3 drives the LED.
  def light(on)
    drive.via2.poke(0x1c02, 0xff)
    drive.via2.poke(0x1c00, on ? 0x08 : 0x00)
  end

  it "sits where the window's LED pane does" do
    require "badline/gui"
    pane = Badline::GUI::DriveLedPane
    expect([described_class::LEFT, described_class::TOP, described_class::WIDTH, described_class::HEIGHT])
      .to eq([pane::LEFT, pane::TOP, pane::WIDTH, pane::HEIGHT])
  end

  it "is bright while the drive lights the LED" do
    light(true)
    expect([led.lit?, led.color]).to eq([true, [0xff, 0x20, 0x20]])
  end

  it "is dim while the LED is off" do
    light(false)
    expect([led.lit?, led.color]).to eq([false, [0x40, 0x00, 0x00]])
  end
end
