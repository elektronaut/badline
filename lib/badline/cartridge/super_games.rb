# frozen_string_literal: true

module Badline
  class Cartridge
    # Super Games: four 16K banks. A write to I/O 2 selects the bank from bits
    # 0-1, switches the ROM out with bit 2, and with bit 3 locks the register
    # until reset.
    class SuperGames < Cartridge
      def poke(addr, value)
        return if addr < 0xdf00 || @locked

        select(value)
        changed!
      end

      private

      def select(value)
        @roml = bank(@roml_banks, value & 0x03)
        @romh = bank(@romh_banks, value & 0x03)
        self.mode = value.anybits?(0x04) ? :off : :rom16k
        @locked = value.anybits?(0x08)
      end

      def install_chips(chips)
        @roml_banks, @romh_banks = banks_from(chips)
        select(0)
      end
    end
  end
end
