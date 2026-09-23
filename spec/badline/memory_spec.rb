# frozen_string_literal: true

require "spec_helper"

describe Badline::Memory do
  let(:memory) { described_class.new }

  it "has a length" do
    expect(memory.length).to eq(65_536)
  end

  it "is zero filled" do
    expect(memory.peek(0xffff)).to eq(0)
  end

  it "can be read as an array" do
    memory = described_class.new([1, 2, 3])
    expect(memory[2]).to eq(3)
  end

  it "can be written as an array" do
    memory[20] = 15
    expect(memory[20]).to eq(15)
  end

  context "with initial state" do
    let(:memory) { described_class.new([0xff, 0x07]) }
    let(:first_bytes) { [memory.peek(0), memory.peek(1)] }

    it "keeps the state" do
      expect(first_bytes).to eq([0xff, 0x07])
    end
  end

  context "with a start location" do
    let(:memory) do
      described_class.new([0xff, 0x07], start: 0x100, length: 2**8)
    end

    it "has a range" do
      expect(memory.range).to eq(0x100..0x1ff)
    end

    it "returns bytes at the proper address" do
      expect(memory[0x101]).to eq(0x07)
    end

    it "raises an error on out of bounds" do
      expect { memory[0x80] }.to raise_error(Badline::Memory::OutOfBoundsError)
    end
  end

  describe "#in_range?" do
    let(:memory) { described_class.new(start: 0x100, length: 2**8) }

    it "returns true if address is in range" do
      expect(memory.in_range?(0x1ff)).to be(true)
    end

    it "returns false if address is not in range" do
      expect(memory.in_range?(0xff)).to be(false)
    end
  end

  describe "#peek16" do
    before { memory.poke(0x100, 1337) }

    it "reads a 16 bit value" do
      expect(memory.peek16(0x100)).to eq(1337)
    end
  end

  describe "#poke" do
    before { memory.poke(0x100, 0x80) }

    it "stores the value" do
      expect(memory.peek(0x100)).to eq(0x80)
    end
  end

  describe "#poke16" do
    before { memory.poke16(0x100, 0x0539) }

    specify { expect(memory.peek(0x100)).to eq(0x39) }
    specify { expect(memory.peek(0x101)).to eq(0x05) }
  end

  describe "#write and #read" do
    before { memory.write(0x2000, [0x0a, 0x09, 0x08, 0x07]) }

    it "writes the bytes" do
      expect(memory.read(0x2000, 4)).to eq([0x0a, 0x09, 0x08, 0x07])
    end
  end

  describe "#clear!" do
    before do
      memory.write(0x2000, [0x0a, 0x09])
      memory.clear!([0xff, 0x07])
    end

    specify { expect(memory.read(0x0000, 3)).to eq([0xff, 0x07, 0x00]) }
    specify { expect(memory.read(0x2000, 2)).to eq([0x00, 0x00]) }
  end
end
