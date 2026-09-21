# frozen_string_literal: true

require "spec_helper"

describe Badline::AddressBus do
  let(:address_bus) { described_class.new }

  specify { expect(address_bus[0x0000]).to eq(0x2f) }
  specify { expect(address_bus[0x0001]).to eq(0b00110111) }

  describe "the processor port" do
    context "when all bits are inputs" do
      before do
        address_bus[0x01] = 0x34
        address_bus[0x00] = 0x00
      end

      specify { expect(address_bus[0x01]).to eq(0x17) }

      it "keeps the ROMs banked in" do
        expect(address_bus[0xa000]).to eq(0x94)
      end
    end

    context "when the ROMs are banked out through output bits" do
      before do
        address_bus[0xa000] = 0x20
        address_bus[0x00] = 0xff
        address_bus[0x01] = 0x34
      end

      specify { expect(address_bus[0x01]).to eq(0x34) }

      it "unmaps the BASIC ROM" do
        expect(address_bus[0xa000]).to eq(0x20)
      end
    end

    context "when bit 5 becomes an input" do
      before { address_bus[0x00] = 0x0f }

      specify { expect(address_bus[0x01] & 0x20).to eq(0) }
    end

    context "when a floating bit was driven high before becoming an input" do
      before do
        address_bus[0x00] = 0xff
        address_bus[0x01] = 0xb7
        address_bus[0x00] = 0x2f
      end

      specify { expect(address_bus[0x01]).to eq(0xb7) }
    end

    context "when a floating bit was driven low before becoming an input" do
      before do
        address_bus[0x00] = 0xff
        address_bus[0x01] = 0x37
        address_bus[0x00] = 0x2f
      end

      specify { expect(address_bus[0x01] & 0x80).to eq(0) }
    end
  end

  it "overlays the ROM" do
    expect(address_bus[0xa000]).to eq(0x94)
  end

  context "when writing through an overlay" do
    before { address_bus[0xa000] = 0x20 }

    specify { expect(address_bus[0xa000]).to eq(0x94) }

    context "when the overlays are disabled" do
      # Disables all overlays
      before { address_bus.disable_overlays! }

      specify { expect(address_bus[0xa000]).to eq(0x20) }
    end
  end

  describe "the pot mux" do
    let(:paddles) { Badline::Input::Paddles.new }

    before do
      address_bus.control_ports.device1 = paddles
      paddles.move(-0x30, 0)
      address_bus[0xdc02] = 0xff
    end

    it "reads a port 1 paddle once CIA 1 PA6 selects it" do
      address_bus[0xdc00] = 0x40
      expect(address_bus[0xd419]).to eq(0x50)
    end

    it "leaves POTX floating while PA6 is low" do
      address_bus[0xdc00] = 0x80
      expect(address_bus[0xd419]).to eq(0xff)
    end
  end
end
