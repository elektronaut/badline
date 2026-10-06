# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # Paints the VIC-I's display a line at a time from what the VIC
      # fetched for it: each character's pattern byte and colour nibble, the
      # pixel its first character starts at and how many it fetched. Each
      # line keeps its own, so the next line's fetches, which can start
      # before this line's last pixels are out, don't overwrite them, and a
      # fetch that reads what the same line read a frame ago changes
      # nothing.
      #
      # A line is painted when its last pixel is out, unless a colour
      # register was written while it was going out: then the pixels up to
      # the write are painted first, with the old colours. Border,
      # background and auxiliary colour take hold from the pixel the write
      # lands on, and the reverse bit two pixels later. A line with the
      # same fetches and colours as the frame before is left alone.
      #
      # A character's colour nibble picks its mode. Below 8 it's a hires
      # character in that colour: a set bit is the character's colour and a
      # clear one the background, or the other way round with $900F bit 3
      # clear. From 8 up it's multicolour, two bits to a double-width pixel:
      # 00 the background, 01 the border, 10 the character's colour (the
      # nibble's low three bits) and 11 the auxiliary colour, whatever
      # $900F bit 3 says (MOS 6560/6561 datasheet, "Color operating modes").
      class Painter
        # The characters a line holds room for. A line fetches at most 34.
        SLOTS = 40

        # What the VIC fetched for each line, SLOTS characters a line, and
        # whether any of it differs from what the line fetched a frame ago.
        attr_reader :patterns, :colors, :counts, :starts, :stale

        attr_reader :display, :width, :dirty_lines, :render

        # +blanked+ is the number of lines at the top of the frame that are
        # never painted.
        def initialize(lines, width, blanked)
          @width = width
          @blanked = blanked
          @display = Array.new(width * lines, 0)
          @dirty_lines = Array.new(lines, true)
          @patterns = Array.new(lines * SLOTS, 0)
          @colors = Array.new(lines * SLOTS, 0)
          @counts = Array.new(lines, 0)
          @starts = Array.new(lines, 0)
          @stale = Array.new(lines, true)
          @memo_keys = Array.new(lines, -1)
          @render = true
        end

        # Clears the display and starts painting +row+, with the colour
        # registers at zero.
        def power_on!(row)
          @border = @background = @aux = 0
          @reverse = true
          @row = row
          @painted = 0
          @written = false
          @counts.fill(0)
          @stale.fill(true)
          @memo_keys.fill(-1)
          @display.fill(0)
          @dirty_lines.fill(true)
        end

        def clear_dirty_lines!
          @dirty_lines.fill(false)
        end

        # Painting can be turned off, and once it's back on every line is
        # painted afresh.
        def render=(value)
          @memo_keys.fill(-1)
          @render = value
        end

        # $900F written while +position+ of the line is going out.
        def colors_written(position, value)
          @written = true
          paint_to(position)
          @border = value & 0x07
          @background = value >> 4
          paint_to(position + 2)
          @reverse = value.nobits?(0x08)
        end

        # The auxiliary colour, $900E bits 7-4, written while +position+ of
        # the line is going out.
        def aux_written(position, aux)
          @written = true
          paint_to(position)
          @aux = aux
        end

        # The current line's last pixel is out: paints what's left of it,
        # then starts +next_row+.
        def finish_line(next_row)
          row = @row
          if @render && row >= @blanked
            key = memo_key(row)
            if @written || @stale[row] || key != @memo_keys[row]
              paint_to(@width)
              @memo_keys[row] = @written ? -1 : key
              @dirty_lines[row] = true
            end
          end
          @stale[row] = false
          @painted = 0
          @written = false
          @row = next_row
        end

        private

        # The colours and the window's place on +row+, packed into one
        # Integer.
        def memo_key(row)
          count = @counts[row]
          start = count.zero? ? 0 : @starts[row]
          @border | (@background << 3) | (@aux << 7) | (@reverse ? 0x800 : 0) | (start << 12) | (count << 24)
        end

        # Paints the current line's pixels from where it got to up to
        # +stop+.
        def paint_to(stop)
          return unless @render && @row >= @blanked

          x = @painted
          return if x >= stop

          @painted = stop
          base = @row * @width
          border_to = @starts[@row]
          border_to = stop if border_to > stop
          x = paint_border(base, x, border_to)
          x = paint_characters(base, x, stop)
          paint_border(base, x, stop)
        end

        # Paints the border from +from+ up to +to+, and returns where it
        # got to.
        def paint_border(base, from, to)
          return from if from >= to

          @display.fill(@border, base + from, to - from)
          to
        end

        # Paints the characters from +from+ up to +stop+, and returns where it
        # got to: +stop+, or the end of the line's characters.
        def paint_characters(base, from, stop)
          x = from
          row = @row
          start = @starts[row]
          finish = start + (@counts[row] * 8)
          slot = row * SLOTS
          while x < stop && x < finish
            first = x - start
            cell = first & ~7
            last = stop - start - cell
            last = 8 if last > 8
            paint_character(base + start + cell, slot + (cell >> 3), first & 7, last)
            x = start + cell + last
          end
          x
        end

        # Paints pixels +first+ up to +last+ of the character in +slot+,
        # whose first pixel is at +at+.
        def paint_character(at, slot, first, last)
          pattern = @patterns[slot]
          color = @colors[slot]
          if color < 8
            paint_hires(at, pattern, color, first, last)
          else
            paint_multicolor(at, pattern, color & 0x07, first, last)
          end
        end

        def paint_hires(at, pattern, color, first, last)
          display = @display
          set = @reverse ? @background : color
          clear = @reverse ? color : @background
          i = first
          while i < last
            display[at + i] = pattern.anybits?(0x80 >> i) ? set : clear
            i += 1
          end
        end

        def paint_multicolor(at, pattern, color, first, last)
          display = @display
          i = first
          while i < last
            pair = (pattern >> (6 - (i & 6))) & 0x03
            display[at + i] =
              if pair.zero? then @background
              elsif pair == 1 then @border
              elsif pair == 2 then color
              else @aux
              end
            i += 1
          end
        end
      end
    end
  end
end
