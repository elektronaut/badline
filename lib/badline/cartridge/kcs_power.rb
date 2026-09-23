# frozen_string_literal: true

module Badline
  class Cartridge
    # The KCS Power Cartridge: 16K of ROM, 128 bytes of RAM and a freeze
    # button. It boots in 16K mode, and any access to I/O 1 sets the lines
    # from address bit 1 and the direction:
    #
    #   read,  bit 1 clear  8K
    #   read,  bit 1 set    off
    #   write, bit 1 clear  16K
    #   write, bit 1 set    Ultimax
    #
    # A read of I/O 1 returns the second last page of ROML. I/O 2 holds the
    # RAM in its lower half, and the upper half reads the EXROM line in bit 7
    # and GAME in bit 6, which the freezer checks to find the mode it
    # interrupted. A freeze switches to Ultimax and lets go of NMI.
    class KCSPower < Cartridge
      include Freezer

      IO1_ROM_PAGE = 0x1e00

      def readable_io_pages
        [0xde, 0xdf]
      end

      def peek(addr)
        if addr < 0xdf00
          switch(addr.anybits?(0x02) ? :off : :rom8k)
          @roml.peek(IO1_ROM_PAGE | (addr & 0xff))
        elsif addr.anybits?(0x80)
          (@exrom << 7) | (@game << 6) | (open_bus(addr) & 0x3f)
        else
          @ram[addr & 0x7f]
        end
      end

      def poke(addr, value)
        if addr < 0xdf00
          switch(addr.anybits?(0x02) ? :ultimax : :rom16k)
        elsif addr.nobits?(0x80)
          @ram[addr & 0x7f] = value
        end
      end

      def reset
        self.nmi = false
        switch(:rom16k)
      end

      def freeze!
        self.nmi = false
        switch(:ultimax)
      end

      private

      def switch(mode)
        self.mode = mode
        changed!
      end

      def install_chips(chips)
        roml, romh = banks_from(chips)
        @roml = roml.first || EMPTY_BANK
        @romh = romh.first || EMPTY_BANK
        @ram = Array.new(0x80, 0xff)
        reset
      end
    end
  end
end
