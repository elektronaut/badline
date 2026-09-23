# frozen_string_literal: true

module Badline
  class Cartridge
    # The Final Cartridge III: four 16K banks, or sixteen on the III+. I/O 1
    # and I/O 2 show the last two pages of the selected ROML bank. A write
    # to $DFFF sets the register:
    #
    #   bits 0-1 bank (0-3 on the III+)
    #   bit 4    EXROM level
    #   bit 5    GAME level
    #   bit 6    NMI line, active low
    #   bit 7    hides the register until the next freeze
    #
    # Clearing bit 6 pulls NMI without freezing, and setting it lets go of
    # NMI after a freeze. A freeze keeps the bank and switches to Ultimax,
    # which the VIC doesn't see until the register sets it again.
    class FinalCartridge3 < Cartridge
      include Freezer

      REGISTER = 0xdfff

      def readable_io_pages
        [0xde, 0xdf]
      end

      def peek(addr)
        @io_bank.peek(addr)
      end

      def poke(addr, value)
        return unless addr == REGISTER && @register_visible

        @register_visible = value.nobits?(0x80)
        self.nmi = value.nobits?(0x40)
        select(value & @bank_mask)
        @exrom = (value >> 4) & 0x01
        @game = (value >> 5) & 0x01
        @phi1_ultimax = ultimax?
        changed!
      end

      def phi1_ultimax?
        @phi1_ultimax
      end

      def reset
        @register_visible = true
        @phi1_ultimax = false
        self.nmi = false
        select(0)
        self.mode = :rom16k
        changed!
      end

      def freeze!
        @register_visible = true
        @phi1_ultimax = false
        self.mode = :ultimax
        changed!
      end

      private

      def select(number)
        @io_bank = @roml = bank(@roml_banks, number)
        @romh = bank(@romh_banks, number)
      end

      def install_chips(chips)
        @roml_banks, @romh_banks = banks_from(chips)
        @bank_mask = @roml_banks.length > 4 ? 0x0f : 0x03
        reset
      end
    end
  end
end
