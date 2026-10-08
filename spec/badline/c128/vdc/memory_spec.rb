# frozen_string_literal: true

require "spec_helper"

# The page layouts VDC/vdcdump's patterns.txt records from real machines.
describe Badline::C128::VDC::Memory do
  def aliases?(memory, first, second)
    memory.store(first, 0)
    memory.store(second, 0x5a)
    memory.fetch(first) == 0x5a
  end

  describe "16K of 4416s in 16K mode" do
    subject(:memory) { described_class.new(16) }

    it "sees 14 bits of address" do
      expect(aliases?(memory, 0x0123, 0x4123)).to be(true)
    end

    it "keeps the 16K apart" do
      expect(aliases?(memory, 0x0123, 0x2123)).to be(false)
    end
  end

  describe "16K of 4416s in 64K mode" do
    subject(:memory) { described_class.new(16).tap { |ram| ram.mode64 = true } }

    it "loses A8, so pages 0 and 1 are one" do
      expect(aliases?(memory, 0x0012, 0x0112)).to be(true)
    end

    it "loses A15, so pages 0 and $80 are one" do
      expect(aliases?(memory, 0x0012, 0x8012)).to be(true)
    end

    it "keeps A14" do
      expect(aliases?(memory, 0x0012, 0x4012)).to be(false)
    end
  end

  describe "64K in 16K mode" do
    subject(:memory) { described_class.new(64) }

    it "puts page 1 at page 3" do
      memory.store(0x0105, 0x77)
      expect(memory.ram[0x0305]).to eq(0x77)
    end

    it "puts page $41 at page 3 too, with A14 on no pin" do
      memory.store(0x4105, 0x77)
      expect(memory.ram[0x0305]).to eq(0x77)
    end

    it "keeps A15" do
      memory.store(0x8205, 0x77)
      expect(memory.ram[0x8405]).to eq(0x77)
    end
  end

  describe "64K in 64K mode" do
    subject(:memory) { described_class.new(64).tap { |ram| ram.mode64 = true } }

    it "maps every address to itself" do
      memory.store(0xc1a5, 0x77)
      expect(memory.ram[0xc1a5]).to eq(0x77)
    end
  end
end
