# frozen_string_literal: true

require "spec_helper"

describe Badline::VIC::Bank do
  subject(:vic_bank) { described_class.new }

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

  describe "#phi1_data" do
    subject { vic_bank.phi1_data }

    before { vic_bank.address_bus.ram.poke(0x3fff, 0xa5) }

    it { is_expected.to eq(0) }

    context "when a phi1 fetch has run" do
      before { vic_bank.peek(0x3fff) }

      it { is_expected.to eq(0xa5) }
    end

    context "when only a phi2 fetch has run" do
      before { vic_bank.peek_phi2(0x3fff) }

      it { is_expected.to eq(0) }
    end
  end

  describe "#peek_color" do
    subject { vic_bank.peek_color(3) }

    before do
      vic_bank.address_bus.ram.poke(0x3fff, 0xf0)
      vic_bank.peek(0x3fff)
      vic_bank.address_bus.color_ram.poke(0xd803, 0x0b)
    end

    it { is_expected.to eq(0x0b) }
  end
end
