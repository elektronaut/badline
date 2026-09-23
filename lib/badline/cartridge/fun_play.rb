# frozen_string_literal: true

module Badline
  class Cartridge
    # Fun Play / Power Play: up to 16 8K banks. A write to I/O 1 selects the
    # bank from bits 3-5 and 0, and either 8K mode ($00 in bits 7, 6, 2 and 1)
    # or no ROM ($86 in those bits).
    class FunPlay < Cartridge
      def poke(addr, value)
        return if addr > 0xdeff

        @roml = bank(@banks, self.class.bank_number(value))
        case value & 0xc6
        when 0x00 then self.mode = :rom8k
        when 0x86 then self.mode = :off
        end
        changed!
      end

      # The CRT file numbers each bank by the register value that selects it.
      def reset
        poke(0xde00, 0)
      end

      def self.bank_number(value)
        ((value >> 3) & 0x07) | ((value & 0x01) << 3)
      end

      private

      def install_chips(chips)
        @banks = []
        chips.each { |chip| @banks[self.class.bank_number(chip.bank)] = rom_bank(chip.data) }
        reset
      end
    end
  end
end
