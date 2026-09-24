# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # = VIC-II Registers
    #
    # == Sprite positions
    #
    #   $D000: Sprite 0 X
    #   $D001: Sprite 0 Y
    #   $D002: Sprite 1 X
    #   $D003: Sprite 1 Y
    #   $D004: Sprite 2 X
    #   $D005: Sprite 2 Y
    #   $D006: Sprite 3 X
    #   $D007: Sprite 3 Y
    #   $D008: Sprite 4 X
    #   $D009: Sprite 4 Y
    #   $D00A: Sprite 5 X
    #   $D00B: Sprite 5 Y
    #   $D00C: Sprite 6 X
    #   $D00D: Sprite 6 Y
    #   $D00E: Sprite 7 X
    #   $D00F: Sprite 7 Y
    #
    #   $D010: Most Significant Bits of Sprites 0-7 Horizontal Position
    #   $D011: Vertical Fine Scrolling and Control Register
    #   $D012: Rasterline
    #          - Read: Current rasterline
    #          - Write: Set rasterline interrupt
    #
    # == Light pen
    #
    #   $D013: Light Pen Horizontal Position
    #   $D014: Light Pen Vertical Position
    #
    #   $D015: Sprite Enable Register
    #   $D016: Horizontal Fine Scrolling and Control Register
    #   $D017: Sprite Vertical Expansion Register
    #   $D018: VIC-II Chip Memory Control Register
    #   $D019: VIC Interrupt Flag Register
    #   $D01A: IRQ Mask Register
    #   $D01B: Sprite to Foreground Display Priority Register
    #   $D01C: Sprite Multicolor Registers
    #   $D01D: Sprite Horizontal Expansion Register
    #
    # == Sprite collision detection
    #
    #   $D01E: Sprite to Sprite Collision Register
    #   $D01F: Sprite to Foreground Collision Register
    #
    # == Color registers
    #
    # All color registers are 4bit, bits 4-7 always read 1.
    #
    #   $D020: Border color
    #   $D021: Background color 0
    #   $D022: Background color 1
    #   $D023: Background color 2
    #   $D024: Background color 3
    #   $D025: Sprite multicolor 0
    #   $D026: Sprite multicolor 1
    #   $D027: Sprite 0 color
    #   $D028: Sprite 1 color
    #   $D029: Sprite 2 color
    #   $D02A: Sprite 3 color
    #   $D02B: Sprite 4 color
    #   $D02C: Sprite 5 color
    #   $D02D: Sprite 6 color
    #   $D02E: Sprite 7 color
    #
    # $D02F-$D03F: Not in use, always reads 0xff
    # $D040-$D3FF: Repeat $D0000 to $D03F every 64 bytes
    class Registers
      include IntegerHelper

      # The raw register bytes, for the per-column reads on the hot path.
      attr_reader :bytes

      # Every register powers on as zero, as in VICE.
      def initialize
        @bytes = Array.new(2**6, 0)
        @irq_line = false
      end

      # True while any enabled latch bit is set in $D019/$D01A. Cached and
      # re-evaluated on writes, since it's checked every cycle.
      def irq_line? = @irq_line

      def [](reg) = @bytes[reg]

      def read(reg)
        case reg
        when 0x1a, 0x20..0x2e then @bytes[reg] | 0xf0
        when 0x1e, 0x1f then read_clear(reg) # collision registers clear on read
        when 0x2f..0x3f then 0xff
        else @bytes[reg]
        end
      end

      def write(reg, value)
        case reg
        when 0x19 # write 1 to clear
          @bytes[reg] &= ~value
          update_irq_line
        when 0x1a # only the four latch bits
          @bytes[reg] = value & 0x0f
          update_irq_line
        else @bytes[reg] = value
        end
      end

      # Graphics modes
      def ecm = @bytes[0x11][6]
      def bmm = @bytes[0x11][5]
      def mcm = @bytes[0x16][4]
      # ECM/BMM from $D011 bits 6-5, MCM from $D016 bit 4.
      def mode = ((@bytes[0x11] >> 4) & 0b110) | ((@bytes[0x16] >> 4) & 0b001)

      def xscroll = @bytes[0x16] & 0b0111
      def yscroll = @bytes[0x11] & 0b0111

      def rsel? = @bytes[0x11].anybits?(0x08)
      def csel? = @bytes[0x16].anybits?(0x08)
      def display_enabled? = @bytes[0x11].anybits?(0x10)

      def char_base = (@bytes[0x18] & 0b1110) * 0x400
      def bitmap_base = (@bytes[0x18] & 0b1000) * 0x400
      def screen_base = (@bytes[0x18] >> 4) * 0x400

      def border = @bytes[0x20] & 0x0f
      def background(index = 0) = @bytes[0x21 + index] & 0x0f

      def raster_target = uint16(@bytes[0x12], (@bytes[0x11] & 0x80) >> 7)

      def latch_irq!(bit)
        @bytes[0x19] |= bit
        update_irq_line
      end

      def latch_raster_irq! = latch_irq!(0x01)

      def collide!(reg, bits)
        return false if bits.zero?

        was_zero = @bytes[reg].zero?
        @bytes[reg] |= bits
        was_zero
      end

      private

      def update_irq_line
        @irq_line = (@bytes[0x19] & @bytes[0x1a]).anybits?(0x0f)
      end

      def read_clear(reg)
        @bytes[reg].tap { @bytes[reg] = 0 }
      end
    end
  end
end
