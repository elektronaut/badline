# frozen_string_literal: true

module Badline
  class C128
    # The 8722 MMU's registers, $D500-$D50B in C128 mode:
    #
    #   $D500 CR: I/O, the ROMs and the RAM bank the CPU sees
    #   $D501-$D504 PCRA-PCRD: preset configurations
    #   $D505 MCR: the CPU (bit 0, 1 for the 8502), FSDIR, GAME and EXROM
    #         in, C64 mode (bit 6) and the 40/80 key
    #   $D506 RCR: common RAM and the VIC's RAM bank
    #   $D507-$D50A P0L, P0H, P1L, P1H: page 0 and page 1 relocation
    #   $D50B VR: the version, 2 banks of version 0
    #
    # The machine powers on in C64 mode with the 8502 running, the state the
    # C128 KERNAL leaves when C= is held at power-on, and every other
    # register at its reset value. In C64 mode the MMU answers nowhere, but
    # the CPU's RAM bank, common RAM and the VIC's bank it holds stay in
    # force. Until C128 mode boots, a reset comes back to C64 mode too.
    class MMU
      MCR_8502 = 0x01
      MCR_C64_MODE = 0x40
      VERSION = 0x20

      # The registers, CR first.
      attr_reader :registers

      def initialize
        @registers = Array.new(12, 0)
        reset!
      end

      def reset!
        @registers.fill(0)
        @registers[5] = MCR_C64_MODE | MCR_8502
        @registers[9] = 0x01
        @registers[11] = VERSION
      end

      def c64_mode? = @registers[5].anybits?(MCR_C64_MODE)

      # :c64 or :c128, the mode MCR bit 6 selects.
      def mode = c64_mode? ? :c64 : :c128

      # The 64K bank the VIC sees, RCR bits 6 and 7.
      def vic_bank = @registers[6] >> 6
    end
  end
end
