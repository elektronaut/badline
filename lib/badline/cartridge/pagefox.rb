# frozen_string_literal: true

module Badline
  class Cartridge
    # Pagefox: two 32K EPROMs and 32K of RAM, seen 16K at a time. A write to
    # $DE80-$DEFF selects the half with bit 1 and the chip with bits 2-3
    # (EPROM, EPROM, RAM, nothing), and switches the cartridge out with
    # bit 4. Writes to the RAM land in the C64's RAM as well.
    class Pagefox < Cartridge
      RAM_CHIP = 2
      EMPTY_CHIP = 3

      def connect(ram:, open_bus:)
        super
        @ram_banks.each { |b| b.backing = ram }
      end

      def poke(addr, value)
        return if addr < 0xde80 || addr > 0xdeff

        select(value)
        changed!
      end

      def reset
        select(0)
        changed!
      end

      private

      def select(value)
        half = (value >> 1) & 0x01
        chip = (value >> 2) & 0x03
        @roml, @romh = window(chip, half)
        self.mode = value.anybits?(0x10) ? :off : :rom16k
      end

      def window(chip, half)
        case chip
        when RAM_CHIP then @ram_banks[half * 2, 2]
        when EMPTY_CHIP then [@open_bus || EMPTY_BANK] * 2
        else
          number = (chip << 1) | half
          [bank(@roml_banks, number), bank(@romh_banks, number)]
        end
      end

      def install_chips(chips)
        @roml_banks, @romh_banks = banks_from(chips)
        @ram_banks = Array.new(4) { RAMBank.new }
        reset
      end
    end
  end
end
