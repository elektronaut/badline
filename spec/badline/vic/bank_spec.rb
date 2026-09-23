# frozen_string_literal: true

require "spec_helper"

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
end
