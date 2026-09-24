# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # The graphics shift register, pixel by pixel, for the groups where a
    # mode or XSCROLL change lands (VICE x64sc `draw_graphics`). The
    # sequencer paints whole bytes everywhere else, which comes to the same
    # thing while nothing changes.
    #
    # The byte a group draws loads at pixel XSCROLL. ECM and BMM take hold at
    # pixel 4 as they rise and at pixel 6 as they fall (the 6569's colour
    # latency), except that BMM falls at pixel 5 out of any mode but hi-res
    # bitmap. MCM takes hold at pixel 4 for the colour lookup but only at
    # pixel 7 for how the register is read, where a rising MCM also resets
    # the multicolour flip-flop. An MCM that falls out of the invalid
    # ECM+MCM mode is a pixel later on both counts: the lookup changes at
    # pixel 5 and the read at the next group's pixel 0. The mode bits are
    # the sequencer's: ECM 4, BMM 2, MCM 1.
    class GraphicsShifter
      ECM_BMM = 0b110
      ECM_MCM = 0b101
      BMM = 0b010

      # The group #draw painted, and which of its pixels are foreground.
      attr_reader :colors, :fg

      def initialize(registers)
        @registers = registers
        @colors = Array.new(8, 0)
        @fg = Array.new(8, false)
        @gbuf = 0
        @vbuf = 0
        @cbuf = 0
        @flop = 0
        @pixel = 0
        @mode_lookup = 0
        @mode_read = 0
        @late_mcm = false
        @late_read = false
      end

      # Rebuilds the state at the end of a group that painted whole bytes:
      # the byte loaded at pixel shift under an unchanging mode.
      def prime(data, screencode, color, shift, mode)
        @mode_lookup = mode
        @mode_read = mode & 1
        @late_read = false
        load(data, screencode, color)
        (8 - shift).times { read_pixel }
      end

      # Draws one group, loading the byte at pixel shift.
      def draw(data, screencode, color, shift, mode)
        i = 0
        while i < 8
          step_mode(i, mode)
          load(data, screencode, color) if i == shift
          pixel = read_pixel
          @colors[i] = lookup(pixel)
          @fg[i] = pixel >= 2
          i += 1
        end
      end

      private

      def step_mode(pixel, mode)
        case pixel
        when 0 then end_late_read
        when 4 then step_lookup(mode)
        when 5 then step_early_fall(mode)
        when 6 then @mode_lookup &= mode | 1
        when 7 then step_read
        end
      end

      def step_lookup(mode)
        @late_mcm = @mode_lookup.allbits?(ECM_MCM) && mode.nobits?(1)
        @mode_lookup = (@mode_lookup & ~1) | (mode & 1) | (@late_mcm ? 1 : 0) | (mode & ECM_BMM)
      end

      def step_early_fall(mode)
        @mode_lookup &= ~1 if @late_mcm
        @mode_lookup &= mode | ~BMM unless @mode_lookup == BMM
      end

      def step_read
        return @late_read = true if @late_mcm

        mcm = @mode_lookup & 1
        @flop = 0 if mcm == 1 && @mode_read.zero?
        @mode_read = mcm
      end

      def end_late_read
        return unless @late_read

        @mode_read = 0
        @late_read = false
      end

      def load(data, screencode, color)
        @gbuf = data
        @vbuf = screencode
        @cbuf = color & 0x0f
        @flop = 1
      end

      def read_pixel
        multicolor = multicolor?
        if @mode_read == 1 && multicolor
          @pixel = @gbuf >> 6 if @flop == 1
        elsif @gbuf.anybits?(0x80)
          @pixel = multicolor && @mode_read.zero? ? 2 : 3
        else
          @pixel = 0
        end
        @gbuf = (@gbuf << 1) & 0xff
        @flop ^= 1
        @pixel
      end

      def multicolor? = @mode_lookup.anybits?(BMM) || @cbuf.anybits?(0x08)

      def lookup(pixel)
        case @mode_lookup
        when 0 then pixel < 2 ? @registers.background : @cbuf
        when 1 then pixel == 3 ? @cbuf & 0x07 : @registers.background(pixel)
        when 2 then pixel < 2 ? @vbuf & 0x0f : @vbuf >> 4
        when 3 then multicolor_bitmap(pixel)
        when 4 then pixel < 2 ? @registers.background(@vbuf >> 6) : @cbuf
        else 0
        end
      end

      def multicolor_bitmap(pixel)
        case pixel
        when 0 then @registers.background
        when 1 then @vbuf >> 4
        when 2 then @vbuf & 0x0f
        else @cbuf
        end
      end
    end
  end
end
