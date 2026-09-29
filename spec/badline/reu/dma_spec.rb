# frozen_string_literal: true

require "spec_helper"

describe Badline::REU::DMA do
  # C64 memory whose every byte reads as the cycle count, as the low byte
  # of a CIA timer would, only counting up.
  let(:bus) do
    Class.new do
      attr_accessor :cycle

      def initialize
        @cycle = 0
      end

      def ram = self

      def peek(_addr) = @cycle

      def poke(_addr, _value); end
    end.new
  end
  let(:ram) { Badline::REU::RAM.new(0x80000, 0x80000) }
  let(:dma) { described_class.new(ram, 0x80000, bus) }

  # Swaps length bytes with BA low from cycle 2 to 5, returning the bytes
  # the REU took in and the cycle the bus came back on.
  def swap(length)
    dma.start(described_class::SWAP, 0x1000, 0, length, 0x80)
    loop do
      dma.cycle!(bus.cycle.between?(2, 5))
      break unless dma.holds_bus?

      bus.cycle += 1
    end
    [Array.new(length) { |i| ram.peek(i) }, bus.cycle]
  end

  # Pinned by REU/reutiming2/e5-m2.
  it "holds a swap's read on the first BA-low cycle open for two cycles" do
    expect(swap(3)).to eq([[0, 4, 7], 9])
  end

  # Pinned by REU/reutiming2/f3-m2 and f4-m2.
  it "makes the last read of a swap on the first BA-low cycle and hands the bus back after its write" do
    expect(swap(2)).to eq([[0, 2], 4])
  end
end
