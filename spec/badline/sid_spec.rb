# frozen_string_literal: true

require "spec_helper"

describe Badline::SID do
  subject(:sid) { described_class.new }

  describe "write-only registers" do
    it "stores a write" do
      sid[0xd404] = 0x21
      expect(sid.register(0x04)).to eq(0x21)
    end

    it "reads back the last byte written to any register" do
      sid[0xd404] = 0x21
      expect(sid[0xd400]).to eq(0x21)
    end

    it "reads $00 before anything has been written" do
      expect(sid[0xd400]).to eq(0x00)
    end

    it "does not read the register that was written" do
      sid[0xd400] = 0x11
      sid[0xd404] = 0x21
      expect(sid[0xd400]).to eq(0x21)
    end

    it "keeps the volume register write-only" do
      sid[0xd418] = 0x0f
      expect(sid.register(0x18)).to eq(0x0f)
    end
  end

  describe "read-only registers" do
    it "ignores a write to OSC3" do
      sid[0xd41b] = 0x42
      expect(sid.osc3).to eq(0x00)
    end

    it "ignores a write to ENV3" do
      sid[0xd41c] = 0x42
      expect(sid.env3).to eq(0x00)
    end

    it "reads OSC3 from the oscillator state" do
      sid.osc3 = 0x7f
      expect(sid[0xd41b]).to eq(0x7f)
    end

    it "reads ENV3 from the envelope state" do
      sid.env3 = 0x3c
      expect(sid[0xd41c]).to eq(0x3c)
    end

    it "reads $00 from OSC3 without synthesis" do
      expect(sid[0xd41b]).to eq(0x00)
    end

    it "leaves the bus holding the value that was read" do
      sid.env3 = 0x3c
      sid[0xd41c]
      expect(sid[0xd400]).to eq(0x3c)
    end
  end

  describe "paddle inputs" do
    let(:pots) { Struct.new(:pot_x, :pot_y).new(0x40, 0x80) }

    it "floats POTX high with no source attached" do
      expect(sid[0xd419]).to eq(0xff)
    end

    it "floats POTY high with no source attached" do
      expect(sid[0xd41a]).to eq(0xff)
    end

    it "reads POTX from an injected source" do
      expect(described_class.new(pots:)[0xd419]).to eq(0x40)
    end

    it "reads POTY from an injected source" do
      expect(described_class.new(pots:)[0xd41a]).to eq(0x80)
    end

    it "takes a source attached after construction" do
      sid.pots = pots
      expect(sid[0xd419]).to eq(0x40)
    end

    it "ignores a write to POTX" do
      sid[0xd419] = 0x00
      expect(sid[0xd419]).to eq(0xff)
    end
  end

  describe "unconnected registers" do
    it "reads $FF" do
      expect(sid[0xd41f]).to eq(0xff)
    end

    it "does not pick up the bus value" do
      sid[0xd400] = 0x42
      expect(sid[0xd41d]).to eq(0xff)
    end
  end

  describe "mirroring" do
    it "writes through a mirror" do
      sid[0xd7e4] = 0x21
      expect(sid.register(0x04)).to eq(0x21)
    end

    it "reads POTX through a mirror" do
      expect(sid[0xd7f9]).to eq(0xff)
    end

    it "reads the unconnected registers through a mirror" do
      expect(sid[0xd43f]).to eq(0xff)
    end
  end
end
