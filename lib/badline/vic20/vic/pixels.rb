# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # The four pixels a cycle, which Vic20::VIC includes. They go into a
      # line buffer, which becomes a line of #display once whole.
      #
      # A character's eight pixels come out over the two cycles that start
      # LOAD_DELAY after its generator fetch, and a cycle without one draws
      # the border. The group a cycle draws belongs PIXEL_DELAY cycles back
      # in the line, so a display line runs from that cycle of one raster
      # line into the start of the next, and a character the horizontal
      # origin puts at cycle n starts at pixel 4n.
      #
      # In a character whose colour nibble has bit 3 clear, each pattern
      # bit picks the character's colour (bits 2-0 of the nibble) or the
      # background, swapped while $900F bit 3 is clear. With bit 3 set,
      # each pair of bits is one double-width pixel: background, border,
      # character colour or auxiliary colour.
      module Pixels
        private

        def draw(column)
          finish_line if column == PIXEL_DELAY
          pos = column < PIXEL_DELAY ? (column + @cycles_per_line - PIXEL_DELAY) << 2 : (column - PIXEL_DELAY) << 2
          slot = @tick & 3
          color = @load_color[slot]
          if color >= 0
            flush_border(pos) if @border_from >= 0
            @load_color[slot] = -1
            @pattern = @load_pattern[slot]
            @pattern_color = color
            @second_half = true
            draw_group(pos, @pattern >> 4)
          elsif @second_half
            @second_half = false
            draw_group(pos, @pattern & 0x0f)
          else
            draw_border(pos)
          end
        end

        def draw_group(pos, bits)
          return draw_split_group(pos, bits) if @colors_changed

          color = @pattern_color
          if color < 8
            draw_hires(pos, @reverse == 1 ? bits ^ 0x0f : bits, color)
          else
            draw_multicolor(pos, bits, color & 0x07)
          end
        end

        def draw_hires(pos, bits, foreground)
          line = @line
          background = @background
          line[pos] = bits.nobits?(0x08) ? background : foreground
          line[pos + 1] = bits.nobits?(0x04) ? background : foreground
          line[pos + 2] = bits.nobits?(0x02) ? background : foreground
          line[pos + 3] = bits.nobits?(0x01) ? background : foreground
        end

        def draw_multicolor(pos, bits, foreground)
          line = @line
          left = multicolor_pixel(bits >> 2, foreground)
          right = multicolor_pixel(bits & 0x03, foreground)
          line[pos] = left
          line[pos + 1] = left
          line[pos + 2] = right
          line[pos + 3] = right
        end

        def multicolor_pixel(pair, foreground)
          case pair
          when 0 then @background
          when 1 then @border
          when 2 then foreground
          else @auxiliary
          end
        end

        # The border runs from +pos+ on until a character or the end of the
        # line ends it, and is drawn then. A colour write splits the run.
        def draw_border(pos)
          if @colors_changed
            flush_border(pos) if @border_from >= 0
            @line[pos] = @old_border
            @border_from = pos + 1
          elsif @border_from.negative?
            @border_from = pos
          end
        end

        # Draws the border from where its run started up to +pos+, in the
        # colour it had until this cycle.
        def flush_border(pos)
          @line.fill(@old_border, @border_from, pos - @border_from)
          @border_from = -1
        end

        # The display line before the one starting now is whole: copies it
        # into the display if it changed.
        def finish_line
          flush_border(@width) if @border_from >= 0
          row = @rasterline.zero? ? @height - 1 : @rasterline - 1
          return unless line_changed?(row)

          @display[row * @width, @width] = @line
          @dirty_lines[row] = true
        end

        def line_changed?(row)
          display = @display
          line = @line
          from = row * @width
          pos = 0
          while pos < @width
            return true if display[from + pos] != line[pos]

            pos += 1
          end
          false
        end
      end
    end
  end
end
