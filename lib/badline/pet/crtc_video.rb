# frozen_string_literal: true

module Badline
  class PET
    # What the CRTC boards make of the CRTC's outputs. Each character the
    # CRTC displays reads the screen RAM at its memory address, MA0-MA9,
    # and the character ROM's row RA0-RA2 from the half VIA CA2 selects.
    # On the 80-column boards each character reads two bytes, at twice the
    # address and the one after, and shows them side by side, 16 dots to a
    # cycle. MA12 low inverts the picture, and RA3 high blanks the line.
    #
    # The picture is a Canvas 273 lines high, 704 dots wide on 80 columns
    # and 384 on 40, framed as xpet frames it. Across, R1's characters sit
    # in the middle as R1, R0 and R2 stand at the start of the frame, and
    # each character shows as far right as it comes after its line's
    # horizontal sync, so a line whose sync moves moves with it. Down, the
    # frame's first line sits where the lines the last frame showed until
    # the display stopped at R6 would sit in the middle (a frame where it
    # never stopped leaves that alone), and each horizontal sync starts the
    # next line of the picture. Nothing shows within MARGIN dots of either
    # side.
    class CRTCVideo
      HEIGHT = 273

      # The dots at each side that xpet leaves black even where the display
      # runs on through horizontal sync.
      MARGIN = 8

      attr_reader :canvas

      # The screen RAM's bytes.
      attr_writer :cells

      def initialize(characters, via, crtc_registers, columns80:)
        @cells = []
        @rows = characters.rows
        @via = via
        @registers = crtc_registers
        @wide = columns80
        @char_shift = columns80 ? 4 : 3
        @canvas = Canvas.new(columns80 ? 704 : 384, HEIGHT, margin: MARGIN)
        @displayed = 200
        @frame_displayed = 0
        @line_shown = false
        @y = 0
        @from_y = 0
        @to_y = 0
        @on_canvas = false
        @origin = 0
        @from = 0
        @to = 0
        frame_start
      end

      def character(address, raster, since_hsync)
        @line_shown = true
        return unless @on_canvas

        x = @origin + (since_hsync << @char_shift)
        @from = x if x < @from
        @to = x if x > @to
        bits = raster.anybits?(0x08) ? 0 : row_bits(address, raster)
        if @wide
          @canvas.paint(x, @y, bits >> 8)
          @canvas.paint(x + 8, @y, bits & 0xff)
        else
          @canvas.paint(x, @y, bits)
        end
      end

      # Horizontal sync takes the beam to the next line of the picture.
      def hsync
        end_canvas_line
        @y += 1
        @on_canvas = @y >= 0 && @y < HEIGHT
      end

      def line_end
        @frame_displayed += 1 if @line_shown
        @line_shown = false
      end

      # The display stops for the rest of the frame after the lines it has
      # shown, which frame the next one.
      def rows_end
        @displayed = @frame_displayed
      end

      def frame_start
        end_canvas_line
        sweep(0, @from_y)
        sweep(@to_y, HEIGHT)
        @frame_displayed = 0
        regs = @registers
        @origin = ((@canvas.width - (regs[1] << @char_shift)) >> 1) - ((regs[0] + 1 - regs[2]) << @char_shift)
        @y = (HEIGHT - (@displayed + 1)) / 2
        @on_canvas = @y >= 0 && @y < HEIGHT
        @from_y = @y.clamp(0, HEIGHT)
        @to_y = @from_y
      end

      private

      # The row's dots, both bytes' on 80 columns, high byte left.
      def row_bits(address, raster)
        set = @via.ca2_output ? Characters::TEXT : 0
        invert = address.anybits?(0x1000) ? 0 : 0xffff
        line = set | (raster & 0x07)
        cell = address & 0x3ff
        if @wide
          left = @rows[line | (@cells[cell << 1] << 3)]
          right = @rows[line | (@cells[(cell << 1) | 1] << 3)]
          ((left << 8) | right) ^ invert
        else
          (@rows[line | (@cells[cell] << 3)] ^ invert) & 0xff
        end
      end

      # Sets the line's span to the characters painted on it.
      def end_canvas_line
        if @on_canvas
          @canvas.span(@y, @from, @to + (1 << @char_shift))
          @to_y = @y + 1
        end
        @from = @canvas.width
        @to = -@canvas.width
      end

      def sweep(from, to)
        y = from
        while y < to
          @canvas.span(y, 0, 0)
          y += 1
        end
      end
    end
  end
end
