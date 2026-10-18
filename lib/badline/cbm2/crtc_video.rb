# frozen_string_literal: true

module Badline
  class CBM2
    # What the B series makes of its 6845's outputs. Each character the
    # CRTC displays reads the 2K screen RAM at its memory address, MA0-MA10,
    # and the character ROM's 16-line glyph for the screen code's low seven
    # bits, from the set TPI1's CA picks: the first 128 glyphs while it is
    # low, the second while it is high. Bit 7 of the screen code reverses
    # the glyph. The ROM's row is the CRTC's raster line, RA0-RA3, so the
    # 600's eight lines show the 8x8 glyphs in the first half of each and
    # the 700's fourteen the 8x16 ones.
    #
    # The cursor is the 6845's: on the character at R14:R15, from line
    # R10's low five bits to line R11, it reverses the dots. R10's bits 5
    # and 6 pick its blink: 00 steady, 01 no cursor, 10 on for 8 fields and
    # off for 8, 11 on for 16 and off for 16.
    #
    # The picture is a PET::Canvas framed as xcbm2 frames its screenshots:
    # 704 dots wide, the first displayed character 32 dots in, and 266
    # lines high with the first row 33 lines down on a 600, or 367 lines
    # with it 8 down on a 700. Each frame paints its displayed lines from
    # there down. A frame laid out otherwise than the last, its lines,
    # rows or sync moved, starts on a black canvas, so nothing the old
    # layout painted stays.
    class CRTCVideo
      LEFT = 32
      WIDTH = 704

      # The lines of the picture and the line its first row starts on, for
      # a 600 and a 700.
      FRAMES = { false => [266, 33], true => [367, 8] }.freeze

      attr_reader :canvas, :frames

      # Whether it paints the characters: a run that never shows the
      # picture can leave it alone.
      attr_accessor :render

      # +characters+ is the character ROM's bytes, +screen+ the screen RAM,
      # +tpi+ TPI1, whose CA picks the set, and +registers+ the CRTC's.
      def initialize(characters, screen, tpi, registers, high_profile:)
        @glyphs = characters
        @screen = screen
        @tpi = tpi
        @registers = registers
        height, @top = FRAMES.fetch(high_profile)
        @canvas = PET::Canvas.new(WIDTH, height)
        @frames = 0
        @line = 0
        @line_shown = false
        @origin = LEFT
        @layout = []
        @render = true
        frame_start
      end

      def character(address, raster, since_hsync)
        @line_shown = true
        y = @top + @line
        return if y >= @canvas.height || !@render

        @canvas.paint(@origin + (since_hsync << 3), y, row_bits(address, raster))
      end

      def hsync; end

      def line_end
        @line += 1 if @line_shown
        @line_shown = false
      end

      def rows_end; end

      # A frame starts painting from the first row's line again, its
      # characters placed so the first one the line displays sits LEFT
      # dots in.
      def frame_start
        regs = @registers
        @frames += 1
        @line = 0
        @origin = LEFT - ((regs[0] + 1 - regs[2]) << 3)
        layout = regs.values_at(0, 1, 2, 4, 5, 6, 9, 12, 13)
        return if layout == @layout

        @layout = layout
        @canvas.clear!
      end

      # The picture under canvas.*, the fields counted, the line the frame
      # paints next and the layout it was framed by, in a keyed snapshot
      # module (BL-VIDEO).
      def save_fields(out)
        out.int("frames", @frames).int("line", @line).bool("line_shown", @line_shown).int("origin", @origin)
        out.ints("layout", @layout)
        @canvas.save_fields(out, "canvas.")
      end

      def load_fields(input)
        @frames = input.int("frames", @frames)
        @line = input.int("line", @line)
        @line_shown = input.bool("line_shown", @line_shown)
        @origin = input.int("origin", @origin)
        @layout = input.ints("layout", @layout).dup
        @canvas.load_fields(input, "canvas.")
      end

      private

      def row_bits(address, raster)
        code = @screen.peek(0xd000 | (address & 0x7ff))
        glyph = (code & 0x7f) | (@tpi.ca? ? 0x80 : 0)
        bits = @glyphs[(glyph << 4) | (raster & 0x0f)]
        bits ^= 0xff if code >= 0x80
        bits ^= 0xff if cursor?(address, raster)
        bits
      end

      def cursor?(address, raster)
        regs = @registers
        return false unless address == ((regs[14] << 8) | regs[15])
        return false if raster < (regs[10] & 0x1f) || raster > regs[11]

        case regs[10] & 0x60
        when 0x00 then true
        when 0x20 then false
        when 0x40 then @frames.nobits?(0x08)
        else @frames.nobits?(0x10)
        end
      end
    end
  end
end
