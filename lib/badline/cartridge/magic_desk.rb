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

      private

      def install_chips(chips)
        @banks = bank_roms(chips, ROML_START)
        @roml = @banks.first
      end
    end
  end
end
