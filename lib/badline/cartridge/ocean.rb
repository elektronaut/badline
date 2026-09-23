# frozen_string_literal: true

module Badline
  class Cartridge
    # Ocean: up to 64 8K banks. A write to I/O 1 selects the bank from bits
    # 0-5, masked to the size of the ROM.
    class Ocean < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        select_bank(value & @bank_mask)
        changed!
      end

      def reset
        select_bank(0)
        changed!
      end

      private

      # In 16K mode the selected bank shows through ROMH as well.
      def select_bank(number)
        @roml = bank(@banks, number)
        @romh = @roml if game.zero?
      end

      def install_chips(chips)
        @banks = banks_from(chips).first
        @bank_mask = bank_mask(@banks) & 0x3f
        reset
      end
    end
  end
end
