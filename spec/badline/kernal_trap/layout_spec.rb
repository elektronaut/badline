# frozen_string_literal: true

require "spec_helper"

describe Badline::KernalTrap::Layout do
  let(:layout) { Badline::KernalTrap::C64_LAYOUT }
  let(:bus) { Badline::Computer.new.address_bus }

  describe "#kernal_mapped?" do
    it "finds the KERNAL in the power-on banking" do
      expect(layout.kernal_mapped?(bus)).to be(true)
    end

    it "finds RAM once the 6510 port banks the KERNAL out" do
      bus.poke(0x00, 0x2f)
      bus.poke(0x01, 0x35)
      expect(layout.kernal_mapped?(bus)).to be(false)
    end
  end

  describe "#release_serial_lines" do
    before do
      bus.poke(0xdd02, 0x3f)
      bus.poke(0xdd00, 0x3b)
    end

    it "lets go of ATN, the clock and the data line" do
      layout.release_serial_lines(bus)
      expect(bus.peek(0xdd00) & 0x38).to eq(0)
    end

    it "returns the port's outputs as it leaves them, the VIC bank bits kept" do
      expect(layout.release_serial_lines(bus) & 0x3f).to eq(0x03)
    end
  end
end
