# frozen_string_literal: true

module Badline
  module Chips
    class TED
      # The picture: a palette index a pixel (Palette), 384 pixels a line
      # and every line of the frame. A line's pixels start at horizontal
      # count 419, so the 40-column window, counts 451-315, runs from pixel
      # 32 to 351, as in xplus4's screenshots.
      #
      # The picture's lines are the scanlines of the frame as they go out,
      # which follow the line count until a write to $FF1C-$FF1D moves it:
      # the frame's scanlines start over where the line count wraps to 0 at
      # the end of the frame, and step with each line otherwise, as in
      # xplus4's screenshots of TED/write-scanline-coarse.
      #
      # A line is painted at column 44, once its last pixel is out, from
      # what the line fetched (Fetches) in the colours of its mode (Modes).
      # A write to a register the picture reads paints the line up to the
      # pixel the write lands on first, so the old value holds to there and
      # the new one from there.
      #
      # Outside the window the border colour ($FF19) shows: above and below
      # it, from the line count reaching line 4 to its reaching line 204 with
      # $FF06 bit 3 set (25 rows), or 8 and 200 (24 rows), so a line count
      # moved past line 4 leaves the frame's window shut;
      # beside it, the 38-column window ($FF07 bit 3 clear) is pixels 39 to
      # 342, as in xplus4's screenshots, where the datasheet's counts would
      # make it 40 to 343. $FF06 bit 4 clear blanks the whole picture to the
      # border colour. A line of the window with no row under way shows the
      # background colour, $FF15.
      #
      # $FF07 bits 0-2 move the characters right by as many pixels, the
      # window's pixels before the first character showing the background.
      module Picture
        WIDTH = 384

        # The horizontal count of a line's first pixel.
        FIRST_COUNT = 419

        # The column whose cycle paints the line, and the first whose writes
        # land on the next line.
        PAINT_COLUMN = 44
        NEXT_LINE_COLUMN = 52

        WINDOW_LEFT = 32
        WINDOW_RIGHT = 352
        NARROW_LEFT = 39
        NARROW_RIGHT = 343

        # How many dots after its cycle's first a register write takes hold:
        # where xplus4 shows a raster interrupt's colour change, a cell
        # boundary with no horizontal scroll.
        WRITE_DELAY = 19

        # The picture, a palette index a pixel.
        attr_reader :display

        # Whether each line has been painted since the front end last
        # cleared them.
        attr_reader :dirty_lines

        # Whether the TED paints its picture. It fetches either way.
        attr_reader :render

        def width = WIDTH

        def height = lines_per_frame

        def clear_dirty_lines!
          @dirty_lines.fill(false)
        end

        def render=(value)
          @render = value
        end

        private

        def reset_picture
          @display = Array.new(WIDTH * 312, 0)
          @dirty_lines = Array.new(312, true)
          @render = true
          @painted = 0
          @scanline = 0
          @window_open = false
          reset_modes
        end

        # The line count steps to +line+: the next scanline, and the
        # window opens or shuts on its first and last lines.
        def step_scanline(line)
          @scanline = (@scanline + 1) % 312
          rows25 = @registers[0x06].anybits?(0x08)
          if line == (rows25 ? 4 : 8)
            @window_open = true
          elsif line == (rows25 ? 204 : 200)
            @window_open = false
          end
        end

        # The line count wraps to 0: the frame's first scanline.
        def end_picture_frame
          @scanline = -1
        end

        # The picture's part of a cycle in +column+.
        def picture_cycle(column)
          return unless column == PAINT_COLUMN

          paint(WIDTH) if @render
          @painted = 0
        end

        # Paints the line up to the pixel a register write lands on.
        def paint_to_write
          return unless @render

          column = @column
          return if column >= PAINT_COLUMN && column < NEXT_LINE_COLUMN

          x = ((column * 8) + WRITE_DELAY - FIRST_COUNT) % 456
          x = WIDTH if x > WIDTH
          paint(x)
        end

        # Paints the line's pixels from where it was left up to +stop+.
        def paint(stop)
          start = @painted
          return if stop <= start

          @painted = stop
          scanline = @scanline
          @dirty_lines[scanline] = true
          base = scanline * WIDTH
          border = @registers[0x19] & 0x7f
          return fill_span(base, start, stop, border) unless @window_open && @registers[0x06].anybits?(0x10)

          narrow = !@registers[0x07].anybits?(0x08)
          left = narrow ? NARROW_LEFT : WINDOW_LEFT
          right = narrow ? NARROW_RIGHT : WINDOW_RIGHT
          fill_span(base, start, stop.clamp(..left), border)
          paint_window(base, start.clamp(left..), stop.clamp(..right))
          fill_span(base, start.clamp(right..), stop, border)
        end

        def fill_span(base, start, stop, color)
          @display.fill(color, base + start, stop - start) if stop > start
        end

        def paint_window(base, start, stop)
          return if stop <= start

          background = @registers[0x15] & 0x7f
          return fill_span(base, start, stop, background) unless @pattern_fetches

          first = WINDOW_LEFT + (@registers[0x07] & 0x07)
          if start < first
            fill_span(base, start, stop.clamp(..first), background)
            start = first
          end
          paint_characters(base, start, stop, first)
        end

        # Paints the characters' pixels +start+ to +stop+, the first
        # character's first pixel at +first+.
        def paint_characters(base, start, stop, first)
          mode = self.mode
          x = start
          while x < stop
            index = (x - first) >> 3
            origin = first + (index << 3)
            to = (origin + 8).clamp(..stop)
            character_colors(index, mode)
            paint_pixels(base, x, to, origin)
            x = to
          end
        end
      end
    end
  end
end
