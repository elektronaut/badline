# frozen_string_literal: true

module Badline
  class Cartridge
    # Comal-80: four 16K banks, or eight with the extra ROMs. A write to
    # I/O 1 selects the bank and the memory configuration. The black board
    # (subtype 0) takes the bank from bits 0-2 and switches the ROM out with
    # bit 6; the grey one (subtype 1) takes the bank from bits 0-1 and the
    # configuration from bits 5-6.
    class Comal80 < Cartridge
      GREY_MODES = %i[rom16k ultimax rom8k off].freeze

      def initialize(crt)
        @grey = crt.subtype == 1
        super
      end

      def poke(addr, value)
        return if addr > 0xdeff

        if @grey
          select(value & 0x03, GREY_MODES[(value >> 5) & 0x03])
        else
          select(value & 0x07, value.anybits?(0x40) ? :off : :rom16k)
        end
        changed!
      end

      def reset
        select(0, :rom16k)
        changed!
      end

      private

      def select(number, mode)
        @roml = bank(@roml_banks, number)
        @romh = bank(@romh_banks, number)
        self.mode = mode
      end

      def install_chips(chips)
        @roml_banks, @romh_banks = banks_from(chips)
        reset
      end
    end
  end
end
