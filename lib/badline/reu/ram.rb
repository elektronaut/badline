# frozen_string_literal: true

module Badline
  class REU
    # The REU's DRAM, as the REC addresses it. The REC counts 19 address
    # bits, 17 on the 1700, and the 1764 fills only the first 256K of
    # them: past that a read finds the latch on the REU's data bus, which
    # holds the last byte the REC moved. A unit past 512K takes its upper
    # address lines from the bank register.
    class RAM
      BANK_SIZE = 0x10000

      # Where a bank of a 1764 that has just been switched on reads
      # inverted, over the first 128K of each 256K. Over the second 128K
      # it is the rest of the bank that reads inverted. Measured from
      # REU/raminitpattern/dumpfile-256k-x1541.bin, a real 1764's dump.
      INVERTED = [0x2a00...0x5400, 0x8000...0xac00, 0xd600...0x10000].freeze

      attr_reader :size
      attr_accessor :latch

      def initialize(size, span)
        @size = size
        @mask = (size > 0x80000 ? size : span) - 1
        @banks = Array.new(size / BANK_SIZE) { [] }
        @power_on = [[], []]
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

      # The latch, and each 64K bank the REC has touched. A bank it hasn't
      # keeps its power-on contents until it does.
      def save_state(out)
        out.int(@latch)
        @banks.each do |bank|
          out.boolean(!bank.empty?)
          out.blob(bank) unless bank.empty?
        end
      end

      def load_state(input)
        @latch = input.int
        @banks.each_index { |number| @banks[number] = input.boolean? ? input.blob : [] }
      end

      private

      # A bank takes its power-on contents the first time it is touched,
      # so an REU costs only the memory a program uses.
      def bank(number)
        bank = @banks[number]
        return bank unless bank.empty?

        half = (number >> 1) & 1
        @power_on[half] = power_on_bank(half == 1) if @power_on[half].empty?
        @banks[number] = @power_on[half].dup
      end

      # Pairs of $FF and $00 bytes, starting with a single $FF, and each
      # odd page the inverse of the even one before it.
      def power_on_bank(upper)
        Array.new(BANK_SIZE) do |offset|
          byte = (offset + 1).anybits?(2) ? 0x00 : 0xff
          byte ^= 0xff if offset.anybits?(0x100)
          inverted = INVERTED.any? { |range| range.cover?(offset) }
          inverted == upper ? byte : byte ^ 0xff
        end
      end
    end
  end
end
