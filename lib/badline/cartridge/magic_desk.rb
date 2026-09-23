# frozen_string_literal: true

module Badline
  class Cartridge
    # Magic Desk: up to 128 8K banks. A write to I/O 1 selects the bank from
    # bits 0-6, masked to the size of the ROM and at least four banks, and
    # switches the ROM out with bit 7.
    class MagicDesk < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        @exrom = value.anybits?(0x80) ? 1 : 0
        @roml = bank(@banks, value & @bank_mask)
        changed!
      end

      def reset
        poke(0xde00, 0)
      end

      private

      def install_chips(chips)
        @banks = banks_from(chips).first
        @bank_mask = (bank_mask(@banks) | 0x03) & 0x7f
        reset
      end
    end
  end
end
