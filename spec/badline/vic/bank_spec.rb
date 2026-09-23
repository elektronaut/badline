# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::VIC::Bank do
  subject(:vic_bank) { described_class.new }

  before do
    vic_bank.address_bus.cia2.poke(0xdd00, 0x03)
    vic_bank.address_bus.cia2.poke(0xdd02, 0x03)
  end

  describe ".start" do
    subject { vic_bank.start }

    it { is_expected.to eq(0x0000) }

    context "when CIA2 register is 00" do
      before { vic_bank.address_bus.cia2.poke(0xdd00, 0b00) }

      it { is_expected.to eq(0xc000) }
    end

    context "when CIA2 register is 01" do
      before { vic_bank.address_bus.cia2.poke(0xdd00, 0b01) }

      it { is_expected.to eq(0x8000) }
    end

    context "when CIA2 register is 10" do
      before { vic_bank.address_bus.cia2.poke(0xdd00, 0b10) }

      it { is_expected.to eq(0x4000) }
    end
  end

  describe "#peek_color" do
    subject { vic_bank.peek_color(3) }

    before do
      vic_bank.address_bus.color_ram.poke(0xd803, 0x0b)
    end

    it { is_expected.to eq(0x0b) }
  end

  context "with a cartridge in Ultimax mode for the CPU's half of the cycle only" do
    include CartridgeBuilder

    before do
      cartridge = build_cartridge(36, (0..3).map { |n| chip(bank: n, fill: 0x10 * (n + 1)) })
      vic_bank.address_bus.attach_cartridge(cartridge)
      vic_bank.address_bus.poke(0xde00, 0x03)
    end

    it "reads the character ROM in the first half" do
      expect(vic_bank.peek(0x1000)).to eq(vic_bank.address_bus.character_rom.peek(0xd000))
    end

    it "reads ROMH in the second half" do
      expect(vic_bank.peek_phi2(0x3000)).to eq(0x10)
    end
  end
end
