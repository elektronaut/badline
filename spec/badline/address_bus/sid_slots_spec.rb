# frozen_string_literal: true

require "spec_helper"

describe Badline::AddressBus::SIDSlots do
  let(:bus) { Badline::AddressBus.new }
  let(:second) { Badline::SID.new(at: 0xd420) }
  let(:third) { Badline::SID.new(at: 0xde00) }

  before do
    bus.add_sid(second)
    bus.add_sid(third)
  end

  it "sends a write in a second SID's 32 bytes to it" do
    bus.poke(0xd421, 0x12)
    expect(second.register(0x01)).to eq(0x12)
  end

  it "keeps the write from the first SID" do
    bus.poke(0xd421, 0x12)
    expect(bus.sid.register(0x01)).to eq(0x00)
  end

  it "leaves the first SID its own registers" do
    bus.poke(0xd401, 0x34)
    expect([bus.sid.register(0x01), second.register(0x01)]).to eq([0x34, 0x00])
  end

  it "leaves the first SID its mirrors on the same page" do
    bus.poke(0xd441, 0x56)
    expect(bus.sid.register(0x01)).to eq(0x56)
  end

  it "decodes only the SID's own 32 bytes" do
    bus.poke(0xd441, 0x56)
    expect(second.register(0x01)).to eq(0x00)
  end

  it "reads from the second SID" do
    bus.poke(0xd425, 0x77)
    expect([bus.peek(0xd425), bus.peek(0xd405)]).to eq([0x77, 0x00])
  end

  it "places a SID in the I/O 1 page" do
    bus.poke(0xde18, 0x0f)
    expect(third.register(0x18)).to eq(0x0f)
  end

  it "leaves the rest of the page on the open bus" do
    expect(bus.peek(0xde20)).to eq(bus.vic.phi1_data)
  end

  context "with the I/O area banked out" do
    before do
      bus.poke(0x00, 0x2f)
      bus.poke(0x01, 0x34)
    end

    it "writes to RAM" do
      bus.poke(0xd421, 0x12)
      expect([second.register(0x01), bus.ram.peek(0xd421)]).to eq([0x00, 0x12])
    end
  end

  context "with the I/O area banked back in" do
    before do
      bus.poke(0x00, 0x2f)
      bus.poke(0x01, 0x34)
      bus.poke(0x01, 0x37)
    end

    it "decodes the SID again" do
      bus.poke(0xd421, 0x12)
      expect(second.register(0x01)).to eq(0x12)
    end
  end
end
