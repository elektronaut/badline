# frozen_string_literal: true

module Badline
  class Cartridge
    # EasyFlash: 64 banks of 8K ROML and 8K ROMH flash, and 256 bytes of RAM
    # at $DF00. $DE00 selects the bank. $DE02 sets the memory configuration:
    # bit 2 hands the GAME line to bit 0 (otherwise the boot jumper holds it
    # low), bit 1 pulls EXROM low and bit 7 drives the LED. The flash reads
    # only; writes to it are ignored.
    class EasyFlash < Cartridge
      def readable_io_pages
        [0xdf]
      end

      def peek(addr)
        @io_ram[addr & 0xff]
      end

      def poke(addr, value)
        if addr >= 0xdf00
          @io_ram[addr & 0xff] = value
        elsif addr.nobits?(0x02)
          select_bank(value & 0x3f)
          changed!
        else
          @control = value & 0x87
          apply_control
          changed!
        end
      end

      def led?
        @control.anybits?(0x80)
      end

      private

      def select_bank(number)
        @roml = bank(@roml_banks, number)
        @romh = bank(@romh_banks, number)
      end

      def apply_control
        game = @control.nobits?(0x04) || @control.anybits?(0x01)
        exrom = @control.anybits?(0x02)
        @game = game ? 0 : 1
        @exrom = exrom ? 0 : 1
      end

      def install_chips(chips)
        @roml_banks, @romh_banks = banks_from(chips)
        @io_ram = Array.new(0x100, 0xff)
        select_bank(0)
        @control = 0
        apply_control
      end
    end
  end
end
