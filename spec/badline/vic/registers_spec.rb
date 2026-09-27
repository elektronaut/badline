# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::Registers do
  subject(:registers) { described_class.new }

  describe "#read" do
    context "with an ordinary register" do
      before { registers.write(0x15, 0xa5) }

      it "returns the stored byte unmasked" do
        expect(registers.read(0x15)).to eq(0xa5)
      end
    end

    context "with the horizontal control register ($D016)" do
      before { registers.write(0x16, 0x08) }

      it "forces the unused bits 7-6 to 1" do
        expect(registers.read(0x16)).to eq(0xc8)
      end
    end

    context "with the memory control register ($D018)" do
      before { registers.write(0x18, 0x14) }

      it "forces the unused bit 0 to 1" do
        expect(registers.read(0x18)).to eq(0x15)
      end
    end

    context "with the interrupt mask register ($D01A)" do
      before { registers.write(0x1a, 0x05) }

      it "forces the unused high bits to 1" do
        expect(registers.read(0x1a)).to eq(0xf5)
      end
    end

    context "with a colour register ($D020-$D02E)" do
      before { registers.write(0x20, 0x03) }

      it "forces the unused high nibble to 1" do
        expect(registers.read(0x20)).to eq(0xf3)
      end
    end

    context "with an unused register ($D02F-$D03F)" do
      before { registers.write(0x2f, 0x12) }

      it "reads 0xff at the bottom of the range, ignoring stored bytes" do
        expect(registers.read(0x2f)).to eq(0xff)
      end

      it "reads 0xff at the top of the range" do
        expect(registers.read(0x3f)).to eq(0xff)
      end
    end
  end

  describe "#write" do
    context "with an ordinary register" do
      before { registers.write(0x18, 0xab) }

      it "stores the value verbatim" do
        expect(registers[0x18]).to eq(0xab)
      end
    end

    context "with the interrupt flag register ($D019)" do
      before { registers.latch_raster_irq! } # sets bit 0

      it "clears flags where a 1 is written" do
        registers.write(0x19, 0x01)
        expect(registers[0x19]).to eq(0)
      end

      it "leaves flags set where a 0 is written" do
        registers.write(0x19, 0x02)
        expect(registers[0x19]).to eq(0x01)
      end
    end

    context "with the interrupt mask register ($D01A)" do
      before { registers.write(0x1a, 0xff) }

      it "masks the value to the four latch bits" do
        expect(registers[0x1a]).to eq(0x0f)
      end
    end
  end
end
