# frozen_string_literal: true

module Badline
  class Cartridge
    # GMod2: 64 8K banks of flash. A write to I/O 1 selects the bank from
    # bits 0-5. Bit 6 selects the EEPROM, which switches the ROM out. The
    # EEPROM and flash writes aren't emulated.
    class GMod2 < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        @roml = bank(@banks, value & 0x3f)
        self.mode = value.anybits?(0x40) ? :off : :rom8k
        changed!
      end

      private

      def install_chips(chips)
        @banks = banks_from(chips).first
        @roml = bank(@banks, 0)
        self.mode = :rom8k
      end
    end
  end
end
