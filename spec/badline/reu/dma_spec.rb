# frozen_string_literal: true

require "spec_helper"

describe Badline::REU::DMA do
  # C64 memory whose every byte reads as the cycle count, as the low byte
  # of a CIA timer would, only counting up.
  let(:bus) do
    Class.new do
      attr_accessor :cycle
      attr_reader :writes

      def initialize
        @cycle = 0
        @writes = []
      end

      def ram = self

      def peek(_addr) = @cycle

      def poke(_addr, _value)
        @writes << @cycle
      end
    end.new
  end
  let(:ram) { Badline::REU::RAM.new(0x80000, 0x80000) }
  let(:dma) { described_class.new(ram, 0x80000, bus) }

  # Swaps length bytes with BA low over the cycles in ba_low, and the bad
  # line's DMA handing BA on to a sprite's on handed_on, returning the
  # bytes the REU took in and the cycle the bus came back on.
  def swap(length, ba_low: 2..5, handed_on: nil)
    dma.start(described_class::SWAP, 0x1000, 0, length, 0x80)
    loop do
      dma.cycle!(ba_low.cover?(bus.cycle), false, bus.cycle == handed_on)
      break unless dma.holds_bus?

      bus.cycle += 1
    end
    [Array.new(length) { |i| ram.peek(i) }, bus.cycle]
  end

  # Fetches length bytes with BA low from cycle 2 to 5, returning the
  # cycles the C64 was written on and the cycle the bus came back on.
  def fetch(length)
    dma.start(described_class::FETCH, 0x1000, 0, length, 0x80)
    loop do
      dma.cycle!((2..5).cover?(bus.cycle), false, false)
      break unless dma.holds_bus?

      bus.cycle += 1
    end
    [bus.writes, bus.cycle]
  end

  it "goes on writing through the first BA-low cycle" do
    expect(fetch(4)).to eq([[0, 1, 2, 6], 7])
  end

  # Pinned by REU/reutiming2/d and d2.
  it "waits for BA to rise before a fetch's last write" do
    expect(fetch(3)).to eq([[0, 1, 6], 7])
  end

  # Pinned by REU/reutiming2/e5-m2.
  it "holds a swap's read on the first BA-low cycle open for two cycles" do
    expect(swap(3)).to eq([[0, 4, 7], 9])
  end

  # Pinned by REU/reutiming2/f3-m2 and f4-m2.
  it "makes the last read of a swap on the first BA-low cycle and hands the bus back after its write" do
    expect(swap(2)).to eq([[0, 2], 4])
  end

  # Pinned by REU/reutiming2/e4-m2, e6-m2 and g3-m2.
  it "reads again when BA rises after it fell between a swap's read and its write" do
    expect(swap(3, ba_low: 3..5)).to eq([[0, 6, 8], 10])
  end

  # Pinned by REU/reutiming2/e4-m2 and e6-m2.
  it "reads again when BA rises after a held read's BA ran on from a bad line to a sprite" do
    expect(swap(3, ba_low: 2..9, handed_on: 6)).to eq([[0, 10, 12], 14])
  end
end
