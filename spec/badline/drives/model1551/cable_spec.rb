# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Drives::Model1551::Cable do
  let(:drive) { Badline::Drives::Model1551.new }
  let(:host) { drive.host_tia }
  let(:tia) { drive.tia }

  it "carries the computer's data lines to the drive" do
    host.poke(0x03, 0xff)
    host.poke(0x00, 0x84)
    expect(tia.peek(0x00)).to eq(0x84)
  end

  it "carries the drive's data lines to the computer" do
    tia.poke(0x03, 0xff)
    tia.poke(0x00, 0x42)
    expect(host.peek(0x00)).to eq(0x42)
  end

  it "pulls the data lines up while neither side drives them" do
    expect(tia.peek(0x00)).to eq(0xff)
  end

  it "carries STATUS0 and STATUS1 to the computer's PB0-1" do
    tia.poke(0x05, 0x1f)
    tia.poke(0x02, 0x02)
    expect(host.peek(0x01)).to eq(0x02)
  end

  it "carries ACK to the computer's PC7" do
    tia.poke(0x05, 0x1f)
    tia.poke(0x02, 0x08)
    expect(host.peek(0x02) & 0x80).to eq(0x80)
  end

  it "carries the computer's DAV to the drive's PC7" do
    host.poke(0x05, 0x40)
    host.poke(0x02, 0x00)
    expect(tia.peek(0x02) & 0x80).to eq(0)
  end

  it "reads 0 on the computer's pins the cable doesn't carry" do
    expect([host.peek(0x01) & 0xfc, host.peek(0x02) & 0x3f]).to eq([0, 0])
  end

  it "lets the computer's TIA read 0 once unplugged" do
    drive.cable.unplug
    expect(host.peek(0x00)).to eq(0)
  end
end
