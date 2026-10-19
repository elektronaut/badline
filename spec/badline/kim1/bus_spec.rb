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

  it "takes RAM in 5K, at $0400-$13FF" do
    bus = Badline::KIM1.new(ram: :"5k").bus
    bus.poke(0x13ff, 0x5a)
    expect([bus.peek(0x13ff), bus.peek(0x33ff), bus.ram_kb]).to eq([0x5a, 0x5a, 5])
  end

  context "when expanded" do
    subject(:bus) { Badline::KIM1.new(ram: :expanded).bus }

    it "takes RAM at $2000-$DFFF of its own" do
      bus.poke(0x0123, 0x11)
      bus.poke(0x2123, 0x22)
      bus.poke(0xdfff, 0x33)
      expect([bus.peek(0x0123), bus.peek(0x2123), bus.peek(0xdfff), bus.ram_kb]).to eq([0x11, 0x22, 0x33, 53])
    end

    it "repeats the first 8K at $E000-$FFFF" do
      bus.poke(0x0123, 0x11)
      expect([bus.peek(0xe123), bus.peek16(0xfffc)]).to eq([0x11, 0x1c22])
    end
  end

  it "says where RAM answers" do
    expect([0x03ff, 0x0400, 0x1780, 0x17ff, 0x1800, 0x23ff].map { |addr| bus.ram?(addr) })
      .to eq([true, false, true, true, false, true])
  end

  it "refuses RAM it can't take" do
    expect { Badline::KIM1.new(ram: :"8k") }.to raise_error(ArgumentError, /8k/)
  end

  it "clears the RAM on power-on" do
    bus.poke(0x03ff, 1)
    bus.poke(0x17ff, 1)
    bus.power_on!
    expect([bus.peek(0x03ff), bus.peek(0x17ff)]).to eq([0, 0])
  end
end
