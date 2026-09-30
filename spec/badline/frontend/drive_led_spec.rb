# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/drive1541_rom"

describe Badline::Frontend::DriveLed do
  subject(:led) { described_class.new(drive) }

  let(:drive) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }

  # VIA 2's port B: PB3 drives the LED.
  def light(on)
    drive.via2.poke(0x1c02, 0xff)
    drive.via2.poke(0x1c00, on ? 0x08 : 0x00)
  end

  it "sits in the bottom right corner of the border" do
    described_class.place
    expect(Badline::SDL.led_rect[0, 16].unpack("l4")).to eq([364, 262, 12, 4])
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
