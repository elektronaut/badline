# frozen_string_literal: true

module Badline
  class Cartridge
    class MagicDesk < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        @exrom = value.anybits?(0x80) ? 1 : 0
        @roml = @banks[(value & 0x3f) % @banks.length]
        changed!
      end

      def reset
        poke(0xde00, 0)
      end

      private

      def install_chips(chips)
        @banks = banks_from(chips).first
        reset
      end
    end
  end
end
