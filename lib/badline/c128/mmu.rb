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
    # The rest of the page reads $FF. $FF00 is CR again, and a write to
    # $FF01-$FF04, the LCRs, copies PCRA-PCRD into CR. Those five answer in
    # every configuration, whatever CR maps there.
    #
    # A write to P0H or P1H waits until the matching P0L or P1L write
    # takes it.
    #
    # A reset clears MCR bit 0, so the Z80 runs first, boots and hands the
    # bus to the 8502. A machine built for C64 mode resets into C64 mode
    # instead, with the 8502 running, the state the C128 KERNAL leaves when
    # C= is held at power-on. In C64 mode the MMU answers nowhere, but the
    # CPU's RAM bank, common RAM and the VIC's bank it holds stay in force.
    class MMU
      CR = 0
      MCR = 5
      RCR = 6
      P0L = 7
      P0H = 8
      P1L = 9
      P1H = 10
      VR = 11

      MCR_8502 = 0x01
      MCR_FSDIR = 0x08
      MCR_C64_MODE = 0x40
      VERSION = 0x20

      # MCR's bits that read back what was written: the CPU, FSDIR and C64
      # mode. Bits 1 and 2 have no pins and read 1.
      MCR_WRITABLE = 0x49
      MCR_UNUSED = 0x06
      MCR_GAME = 0x10
      MCR_EXROM = 0x20
      MCR_DISPLAY_KEY = 0x80

      # The common RAM sizes RCR bits 0-1 pick, in pages.
      COMMON_PAGES = [4, 16, 32, 64].freeze

      # The registers, CR first.
      attr_reader :registers

      # Whether the 40/80 DISPLAY key is locked down, which MCR bit 7 reads
      # as 0 in C128 mode.
      attr_accessor :display_key

      # The cartridge's GAME and EXROM lines, which MCR bits 4 and 5 read.
      attr_writer :game, :exrom

      # +mode+ is the mode a reset leaves, :c128 or :c64.
      def initialize(mode = :c64)
        @reset_mode = mode
        @registers = Array.new(12, 0)
        @display_key = false
        @game = 1
        @exrom = 1
        @on_change = nil
        @on_fast_serial_change = nil
        reset!
      end

      # Calls the block whenever the mapping the registers ask for changes.
      def on_change(&block)
        @on_change = block
      end

      # Calls the block whenever FSDIR turns the fast serial buffers round.
      def on_fast_serial_change(&block)
        @on_fast_serial_change = block
      end

      def reset!
        fast_serial_out = fast_serial_out?
        @registers.fill(0)
        @registers[MCR] = @reset_mode == :c64 ? MCR_C64_MODE | MCR_8502 : 0
        @registers[P1L] = 0x01
        @registers[VR] = VERSION
        @p0h_latch = 0
        @p1h_latch = 0
        @on_change&.call
        @on_fast_serial_change&.call if fast_serial_out
      end

      def c64_mode? = @registers[MCR].anybits?(MCR_C64_MODE)

      # Whether MCR bit 3, FSDIR, turns the fast serial buffers outwards, so
      # CIA 1's CNT and SP drive SRQ and DATA.
      def fast_serial_out? = @registers[MCR].anybits?(MCR_FSDIR)

      # Whether MCR bit 0 gives the bus to the Z80.
      def z80? = @registers[MCR].nobits?(MCR_8502)

      # :c64 or :c128, the mode MCR bit 6 selects.
      def mode = c64_mode? ? :c64 : :c128

      # The 64K bank the VIC sees, RCR bit 6. Bit 7 picks banks a 256K
      # machine has.
      def vic_bank = (@registers[RCR] >> 6) & 0x01

      # The RAM bank the CPU sees, CR bit 6.
      def cpu_bank = (@registers[CR] >> 6) & 0x01

      def cr = @registers[CR]

      # The pages from $0000 up that common RAM keeps in bank 0, or 0.
      def common_low_pages = @registers[RCR].anybits?(0x04) ? common_pages : 0

      # The first page of the common RAM below $FFFF, or 256 for none.
      def common_high_start = @registers[RCR].anybits?(0x08) ? 256 - common_pages : 256

      # The page and the bank page 0 moves to.
      def p0_page = @registers[P0L]
      def p0_bank = @registers[P0H] & 0x01

      # The page and the bank page 1 moves to.
      def p1_page = @registers[P1L]
      def p1_bank = @registers[P1H] & 0x01

      # The registers at $D500-$D5FF.
      def peek(addr)
        offset = addr & 0xff
        case offset
        when MCR then mcr
        when P0H, P1H then 0xf0 | @registers[offset]
        when 0..VR then @registers[offset]
        else 0xff
        end
      end

      def poke(addr, value)
        offset = addr & 0xff
        case offset
        when P0H then @p0h_latch = value & 0x0f
        when P1H then @p1h_latch = value & 0x0f
        when P0L then relocate(P0L, P0H, @p0h_latch, value)
        when P1L then relocate(P1L, P1H, @p1h_latch, value)
        when CR..RCR then write(offset, value)
        end
      end

      # The registers and the P0H and P1H writes waiting for P0L and P1L.
      # The bus maps the restored registers once its own state is back.
      def save_state(out)
        out.ints(@registers).int(@p0h_latch).int(@p1h_latch)
      end

      def load_state(input)
        input.ints_into(@registers)
        @p0h_latch = input.int
        @p1h_latch = input.int
      end

      # CR and the LCRs at $FF00-$FF04: an LCR reads its PCR.
      def peek_configuration(addr) = @registers[addr & 0x07]

      def poke_configuration(addr, value)
        offset = addr & 0x07
        write(CR, offset.zero? ? value : @registers[offset])
      end

      private

      def common_pages = COMMON_PAGES[@registers[RCR] & 0x03]

      def mcr
        value = (@registers[MCR] & MCR_WRITABLE) | MCR_UNUSED
        value |= MCR_GAME if @game == 1
        value |= MCR_EXROM if @exrom == 1
        value |= MCR_DISPLAY_KEY unless @display_key
        value
      end

      def relocate(low, high, latch, value)
        @registers[high] = latch
        write(low, value)
      end

      def write(offset, value)
        fast_serial_out = fast_serial_out?
        @registers[offset] = value
        @on_change&.call
        @on_fast_serial_change&.call if fast_serial_out? != fast_serial_out
      end
    end
  end
end
