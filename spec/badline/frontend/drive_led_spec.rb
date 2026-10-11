# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/drive1541_rom"

describe Badline::Frontend::DriveLed do
  subject(:led) { described_class.new(computer) }

  let(:drive) { Badline::Drives::Model1541.new(rom: Drive1541ROM.stub) }
  let(:computer) { Struct.new(:true_drive).new(drive) }

  # VIA 2's port B: PB3 drives the LED.
  def light(on)
    drive.via2.poke(0x1c02, 0xff)
    drive.via2.poke(0x1c00, on ? 0x08 : 0x00)
  end

  it "sits in the bottom right corner of the border" do
    described_class.place(384, 272)
    expect(Badline::SDL.led_rect[0, 16].unpack("l4")).to eq([364, 262, 12, 4])
  end

  it "puts the power LED left of the activity LED" do
    described_class.place(384, 272, described_class::POWER_OFFSET)
    expect(Badline::SDL.led_rect[0, 16].unpack("l4")).to eq([348, 262, 12, 4])
  end

  it "is bright while the drive lights the LED" do
    light(true)
    expect([led.lit?, led.color]).to eq([true, [0xff, 0x20, 0x20]])
  end

  it "is dim while the LED is off" do
    light(false)
    expect([led.lit?, led.color]).to eq([false, [0x40, 0x00, 0x00]])
  end

  it "keeps a 1541's power LED lit" do
    expect([led.power_lit?, led.power_color]).to eq([true, [0x20, 0xff, 0x20]])
  end

  context "with a 1581" do
    let(:drive) { instance_double(Badline::Drives::Model1581, led_on?: false, power_led_on?: false) }

    it "dims the power LED while the drive flashes it off" do
      expect([led.power_lit?, led.power_color]).to eq([false, [0x00, 0x40, 0x00]])
    end
  end

  context "without a true drive" do
    let(:drive) { nil }

    it "isn't shown" do
      expect(led.shown?).to be(false)
    end

    it "shows once a drive is plugged in" do
      computer.true_drive = Badline::Drives::Model1541.new(rom: Drive1541ROM.stub)
      expect(led.shown?).to be(true)
    end
  end
end
