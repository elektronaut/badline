# frozen_string_literal: true

module Badline
  class Cartridge
    # RGCD: up to eight 8K banks. A write to I/O 1 selects the bank from the
    # low bits, and bit 3 switches the ROM out until reset. The Hucky board
    # (subtype 1) inverts the bank bits and decodes only as many as it has
    # banks.
    class RGCD < Cartridge
      def initialize(crt)
        @hucky = crt.subtype == 1
        super
      end

      def poke(addr, value)
        return if addr > 0xdeff || @disabled

        select(value)
        changed!
      end

      def reset
        @disabled = false
        self.mode = :rom8k
        select(0)
        changed!
      end

      private

      def select(value)
        value ^= 0x07 if @hucky
        if value.anybits?(0x08)
          @disabled = true
          self.mode = :off
        else
          @roml = bank(@banks, value & @bank_mask)
        end
      end

      def install_chips(chips)
        @banks = banks_from(chips).first
        @bank_mask = @hucky ? bank_mask(@banks) : 0x07
        reset
      end
    end
  end
end
