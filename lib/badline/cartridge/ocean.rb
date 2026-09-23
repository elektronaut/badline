# frozen_string_literal: true

module Badline
  class Cartridge
    class Ocean < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        select_bank((value & 0x3f) % @banks.length)
        changed!
      end

      def reset
        select_bank(0)
        changed!
      end

      private

      # In 16K mode the selected bank shows through ROMH as well.
      def select_bank(number)
        @roml = @banks[number]
        @romh = @roml if game.zero?
      end

      def install_chips(chips)
        @banks = banks_from(chips).first
        reset
      end
    end
  end
end
