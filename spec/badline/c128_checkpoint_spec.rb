# frozen_string_literal: true

require "spec_helper"

describe Badline::C128Checkpoint do
  let(:machine) { Badline::C128.new(mode: :c128) }
  let(:before) { described_class.take(machine) }

  def changed_by
    before
    yield
    described_class.take(machine).differences(before)
  end

  describe ".take" do
    it "records the cycle count" do
      3.times { machine.cycle! }
      expect(described_class.take(machine).cycle).to eq(3)
    end

    it "gives two fresh machines the same digests" do
      expect(described_class.take(Badline::C128.new(mode: :c128))).to eq(before)
    end

    it "notices a write to RAM bank 1 in the RAM alone" do
      expect(changed_by { machine.ram.poke(0x11234, 0x55) }).to eq(["ram"])
    end

    it "notices a CIA 1 register" do
      expect(changed_by { machine.cia1.poke(0xdc02, 0x3f) }).to eq(["cia1"])
    end

    it "notices a VDC register in the VDC alone" do
      expect(changed_by { machine.vdc.registers[26] = 0x55 }).to eq(["vdc"])
    end

    it "notices the VDC's RAM in its RAM alone" do
      expect(changed_by { machine.vdc.ram[0x0100] = 0x55 }).to eq(["vdc_ram"])
    end

    it "notices an MMU register" do
      expect(changed_by { machine.mmu.poke(0xd502, 0x12) }).to eq(["mmu"])
    end

    it "notices a Z80 register" do
      expect(changed_by { machine.z80.b = 0x12 }).to eq(["z80"])
    end
  end

  describe ".parse" do
    it "reads back what #to_s writes" do
      expect(described_class.parse(before.to_s)).to eq(before)
    end
  end
end
