# frozen_string_literal: true

require "spec_helper"

# The map is the KIM-1 User Manual's figures 3.12 and 3.13.
describe Badline::KIM1::Bus do
  subject(:bus) { kim.bus }

  let(:kim) { Badline::KIM1.new }

  it "repeats the RAM through every 8K" do
    bus.poke(0x0123, 0x5a)
    expect([bus.peek(0x2123), bus.peek(0xe123)]).to eq([0x5a, 0x5a])
  end

  it "reads the monitor's vectors at $FFFA-$FFFF" do
    expect([0xfffa, 0xfffc, 0xfffe].map { |addr| bus.peek16(addr) }).to eq([0x1c1c, 0x1c22, 0x1c1f])
  end

  it "reads the tape ROM at $1800" do
    expect(bus.peek(0x1800)).to eq(Badline::ROM.read("kim1/6530-003.rom").first)
  end

  it "ignores writes to ROM" do
    bus.poke(0x1c00, 0x00)
    expect(bus.peek(0x1c00)).to eq(0x85)
  end

  it "reads the last byte on the bus where nothing answers" do
    bus.peek(0x1c00)
    expect([bus.peek(0x0400), bus.peek(0x1600)]).to eq([0x85, 0x85])
  end

  it "keeps 64 bytes of RAM in each 6530" do
    bus.poke(0x1780, 0x11)
    bus.poke(0x17c0, 0x22)
    expect([kim.u3.ram.first, kim.u2.ram.first, bus.peek(0x17bf)]).to eq([0x11, 0x22, 0x00])
  end

  it "puts U3's registers at $1700 and U2's at $1740, repeated every 16" do
    bus.poke(0x1703, 0x0f)
    bus.poke(0x1741, 0x7f)
    expect([kim.u3.peek(0x03), kim.u2.peek(0x01), bus.peek(0x1733), bus.peek(0x1771)]).to eq([0x0f, 0x7f, 0x0f, 0x7f])
  end

  it "clears the RAM on power-on" do
    bus.poke(0x03ff, 1)
    bus.poke(0x17ff, 1)
    bus.power_on!
    expect([bus.peek(0x03ff), bus.peek(0x17ff)]).to eq([0, 0])
  end
end
