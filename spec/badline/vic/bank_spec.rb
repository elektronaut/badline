# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::VIC::Bank do
  subject(:vic_bank) { bus.vic.vic_bank }

  let(:bus) { Badline::AddressBus.new }

  before do
    bus.cia2.poke(0xdd00, 0x03)
    bus.cia2.poke(0xdd02, 0x03)
  end

  describe ".start" do
    subject { vic_bank.start }

    it { is_expected.to eq(0x0000) }

    context "when CIA2 register is 00" do
      before { bus.cia2.poke(0xdd00, 0b00) }

      it { is_expected.to eq(0xc000) }
    end

    context "when CIA2 register is 01" do
      before { bus.cia2.poke(0xdd00, 0b01) }

      it { is_expected.to eq(0x8000) }
    end

    context "when CIA2 register is 10" do
      before { bus.cia2.poke(0xdd00, 0b10) }

      it { is_expected.to eq(0x4000) }
    end
  end

  # Pinned by fetchsplit on the 8565.
  describe "#sample_lines" do
    let(:cia2) { bus.cia2 }

    before do
      cia2.poke(0xdd00, 0b10)
      vic_bank.sample_lines
    end

    def swap(register, value)
      cia2.poke(register, value)
      vic_bank.sample_lines
      vic_bank.start
    end

    it "shows bank 3 for the cycle after a write swaps the bank lines" do
      expect(swap(0xdd00, 0b01)).to eq(0xc000)
    end

    it "shows the new bank from the cycle after that" do
      swap(0xdd00, 0b01)
      vic_bank.sample_lines
      expect(vic_bank.start).to eq(0x8000)
    end

    it "shows the new bank at once when only one line moves" do
      expect(swap(0xdd00, 0b11)).to eq(0x0000)
    end

    it "shows the new bank at once when both lines move the same way" do
      cia2.poke(0xdd00, 0b00)
      vic_bank.sample_lines
      expect(swap(0xdd00, 0b11)).to eq(0x0000)
    end

    it "shows the new bank at once when the DDR swaps the lines" do
      cia2.poke(0xdd00, 0b00)
      cia2.poke(0xdd02, 0b01)
      vic_bank.sample_lines
      expect(swap(0xdd02, 0b10)).to eq(0x8000)
    end
  end

  describe "#peek_color" do
    subject { vic_bank.peek_color(3) }

    before do
      bus.color_ram.poke(0xd803, 0x0b)
    end

    it { is_expected.to eq(0x0b) }
  end

  context "with a cartridge in Ultimax mode for the CPU's half of the cycle only" do
    include CartridgeBuilder

    before do
      cartridge = build_cartridge(36, (0..3).map { |n| chip(bank: n, fill: 0x10 * (n + 1)) })
      bus.attach_cartridge(cartridge)
      bus.poke(0xde00, 0x03)
    end

    it "reads the character ROM in the first half" do
      expect(vic_bank.peek(0x1000)).to eq(bus.character_rom.peek(0xd000))
    end

    it "reads ROMH in the second half" do
      expect(vic_bank.peek_phi2(0x3000)).to eq(0x10)
    end

    it "reads RAM again once the cartridge leaves Ultimax mode" do
      bus.poke(0xde00, 0x00)
      expect(vic_bank.peek_phi2(0x3000)).to eq(bus.ram.peek(0x3000))
    end
  end

  context "with memory a machine places at other bases" do
    subject(:vic_bank) { Badline::VIC.new.vic_bank }

    let(:ram) { Badline::Memory.new(Array.new(2**17) { |addr| addr >> 12 }, length: 2**17) }
    let(:rom) { Badline::ROM.new(Array.new(0x2000) { |addr| addr >> 8 }, length: 0x2000) }
    let(:color_ram) { Badline::ColorMemory.new(Badline::VIC.new, start: 0, length: 0x800) }

    it "reads RAM from the base of the VIC's 64K" do
      vic_bank.map(ram, base: 0x10000)
      expect(vic_bank.peek(0x2000)).to eq(0x12)
    end

    it "reads the character ROM from its base" do
      vic_bank.map_character_rom(rom, base: 0x0000)
      expect(vic_bank.peek(0x1100)).to eq(0x11)
    end

    it "reads RAM under the character ROM when the shadow is off" do
      vic_bank.map(ram)
      vic_bank.map_character_rom(rom, shadow: false)
      expect(vic_bank.peek(0x1000)).to eq(0x01)
    end

    it "reads colour RAM from its base" do
      color_ram.poke(0x403, 0x0b)
      vic_bank.connect(cia2: Badline::CIA.new(start: 0xdd00), color_ram:, color_base: 0x400)
      expect(vic_bank.peek_color(3)).to eq(0x0b)
    end
  end
end
