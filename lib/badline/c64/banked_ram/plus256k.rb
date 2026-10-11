# frozen_string_literal: true

module Badline
  module BankedRAM
    # The +256K: four 64K banks, the first of them the machine's own RAM.
    # $D100 picks one for $0000-$0FFF (bits 0-1), one for the VIC (bits 2-3)
    # and one for $1000-$FFFF (bits 6-7). Setting bit 4 locks the register
    # until the next reset.
    class Plus256k
      include Banking

      def initialize(ram)
        @banks = [ram, Memory.new, Memory.new, Memory.new]
        @on_change = nil
        reset!
      end

      def poke(_addr, value)
        return if @locked

        @low_ram = @banks[value & 0b11]
        @video_ram = @banks[(value >> 2) & 0b11]
        @high_ram = @banks[value >> 6]
        @locked = value.anybits?(0x10)
        @on_change&.call
      end

      def reset!
        @low_ram = @video_ram = @high_ram = @banks[0]
        @locked = false
      end

      def type = :plus256k

      def save_state(out)
        [@low_ram, @video_ram, @high_ram].each { |bank| out.int(@banks.index(bank)) }
        out.boolean(@locked)
        @banks.drop(1).each { |bank| bank.save_state(out) }
      end

      def load_state(input)
        @low_ram = @banks.fetch(input.int)
        @video_ram = @banks.fetch(input.int)
        @high_ram = @banks.fetch(input.int)
        @locked = input.boolean?
        @banks.drop(1).each { |bank| bank.load_state(input) }
      end

      def power_on!
        @banks.drop(1).each(&:clear!)
      end
    end
  end
end
