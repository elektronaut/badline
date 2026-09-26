# frozen_string_literal: true

module Badline
  class REU
    # The REU's DRAM, as the REC addresses it. The REC counts 19 address
    # bits, and the 1764 fits DRAM behind only the first 256K of them: the
    # rest read the latch that drives the REU's data bus, which holds the
    # last byte the REC moved. A bigger REU latches the bank register's top
    # bits straight onto its DRAM.
    class RAM
      BANK_SIZE = 0x10000

      # The stretches of each bank that the power-on pattern inverts, for
      # the first and the second half of each 256K.
      INVERTED = [
        [[0x2a00, 0x5400], [0x8000, 0xac00], [0xd600, 0x10000]],
        [[0x0000, 0x2a00], [0x5400, 0x8000], [0xac00, 0xd600]]
      ].freeze

      attr_reader :size
      attr_accessor :latch

      def initialize(size, wrap)
        @size = size
        @mask = (size > 0x80000 ? size : wrap) - 1
        @banks = Array.new(size / BANK_SIZE) { [] }
        @patterns = [[], []]
        @latch = 0xff
      end

      def peek(addr)
        addr &= @mask
        addr < @size ? bank(addr >> 16)[addr & 0xffff] : @latch
      end

      def poke(addr, value)
        addr &= @mask
        bank(addr >> 16)[addr & 0xffff] = value if addr < @size
      end

      private

      # Banks are filled with the power-on pattern the first time they are
      # touched, so an REU costs only the memory a program uses.
      def bank(number)
        bank = @banks[number]
        return bank unless bank.empty?

        @banks[number] = power_on_pattern(number % 4 < 2 ? 0 : 1).dup
      end

      # The pattern VICE measured on a 1764: bytes alternate in pairs
      # between $00 and $ff, inverted every other page, and inverted again
      # over stretches that differ between the two halves of each 256K.
      def power_on_pattern(half)
        pattern = @patterns[half]
        return pattern unless pattern.empty?

        inverted = INVERTED[half]
        BANK_SIZE.times do |offset|
          value = ((offset + 1) >> 1).odd? ? 0x00 : 0xff
          value ^= 0xff if (offset >> 8).odd?
          value ^= 0xff if inverted.any? { |range| offset >= range[0] && offset < range[1] }
          pattern << value
        end
        pattern
      end
    end
  end
end
