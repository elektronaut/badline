# frozen_string_literal: true

require "spec_helper"

describe Badline::ColorMemory do
  let(:address_bus) { Badline::AddressBus.new }
  let(:color_ram) { address_bus.color_ram }

  describe "a CPU read" do
    subject { address_bus.peek(0xd805) }

    before do
      address_bus.ram.poke(0x3fff, 0xa5)
      55.times { address_bus.vic.cycle! } # Bauer cycle 56 idles at $3fff
      address_bus.poke(0xd805, 0x3c)
    end

    it { is_expected.to eq(0xac) }
  end

  describe "at power-on" do
    subject { color_ram.read(0xd800, 0x400).uniq }

    it { is_expected.to eq([0]) }
  end

  describe "#poke" do
    subject { color_ram.nibble(0xd800) }

    before { color_ram.poke(0xd800, 0xf9) }

    it { is_expected.to eq(0x09) }
  end

  describe "a running machine" do
    let(:runs) do
      Array.new(2) do
        computer = Badline::Computer.new
        20_000.times { computer.cycle! }
        (0xd800..0xdbff).map { |addr| computer.address_bus.peek(addr) }
      end
    end

    it "reads back the same bytes on every run" do
      expect(runs.uniq.size).to eq(1)
    end
  end
end
