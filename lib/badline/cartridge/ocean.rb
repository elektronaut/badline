# frozen_string_literal: true

module Badline
  class Cartridge
    class Ocean < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        select_bank((value & 0x3f) % @roml_banks.length)
        changed!
      end

      private

      def select_bank(number)
        @roml = @roml_banks[number]
        @romh = @romh_banks[number] unless @romh_banks.empty?
      end

      def install_chips(chips)
        @roml_banks = bank_roms(chips, ROML_START)
        # A 16K Ocean cartridge mirrors each bank into ROMH as well.
        @romh_banks = game.zero? ? bank_roms(chips, ROMH_START) : []
        select_bank(0)
      end
    end
  end
end
