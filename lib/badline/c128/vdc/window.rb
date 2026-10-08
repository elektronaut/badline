# frozen_string_literal: true

module Badline
  class C128
    class VDC
      # Paints the characters of a displayed line, R1 of them from the
      # line's first dot, in text mode or, with R25 bit 7, bitmap mode.
      #
      # Within a character the pixels come from R22: bits 4-7 hold its width
      # less one (the width itself in double-width mode), and bits 0-3 the
      # last pixel it displays (one more in double-width mode); a value past
      # the width displays all of it. R25 bits 0-3 scroll the line left by
      # the width less one less their value: the first character's pattern
      # loads that many pixels before the display starts, and the displayed
      # pixels run from the load to the R22 bits 0-3 count, as the
      # Programmer's Reference Guide's table for R25 has it. Pixels past a
      # pattern's eighth or the displayed count are the background, or with
      # R25 bit 5, the semigraphic mode, the last displayed pixel repeated.
      #
      # Rows of characters are R9 + 1 lines, of which lines 0 to R23 display
      # the pattern and the rest the background. R24 bits 0-4 scroll the
      # frame up by that many lines. Row r reads its characters from
      # R12/R13 + r * (R1 + R27) and their attributes from R20/R21 likewise,
      # with both start addresses latched as each frame begins.
      #
      # In text mode a character's pattern is 16 bytes in its set, or 32
      # with R9 above 15, from R28 bits 5-7 (bits 6-7 with 32). With
      # attributes, R25 bit 6, bits 0-3 of the attribute are the colour, bit
      # 4 blinks the character into the background, bit 5 underlines it on
      # R29's line, bit 6 reverses it and bit 7 takes it from the second
      # set. Without them the colour is R26 bits 4-7. The cursor, at R14/R15,
      # reverses lines R10 bits 0-4 up to R11 less one, wrapping past the end
      # of the character, and R10 bits 5-6 hold it solid, off, or blinking
      # at 1/16 or 1/32 of the frame rate. Characters blink at 1/16 of the
      # frame rate, or 1/32 with R24 bit 5. R24 bit 6 reverses everything.
      #
      # In bitmap mode scan line n of the frame reads its bytes from
      # R12/R13 + n * (R1 + R27), and the attribute of each character cell
      # holds its foreground in bits 0-3 and background in bits 4-7, or
      # without attributes R26 holds them the other way round. The cursor
      # isn't shown.
      class Window
        def initialize(registers, memory)
          @registers = registers
          @memory = memory
          @display_start = 0
          @attribute_start = 0
          @layout = Array.new(16, 0)
          @pattern = 0
          @foreground = 0
          @background = 0
        end

        def latch_starts
          regs = @registers
          @display_start = (regs[12] << 8) | regs[13]
          @attribute_start = (regs[20] << 8) | regs[21]
        end

        def save_state(out)
          out.int(@display_start).int(@attribute_start)
        end

        def load_state(input)
          @display_start = input.int
          @attribute_start = input.int
        end

        def paint(line, row, row_line, frame)
          regs = @registers
          lay_out_cell
          height = (regs[9] & 0x1f) + 1
          content = (row * height) + row_line + (regs[24] & 0x1f)
          char_line = content % height
          @gap_line = char_line > (regs[23] & 0x1f)
          @stride = regs[1] + regs[27]
          @attributes_on = regs[25].anybits?(0x40)
          @screen_reverse = regs[24].anybits?(0x40)
          if regs[25].anybits?(0x80)
            paint_bitmap(line, content, content / height)
          else
            paint_text(line, content / height, char_line, frame)
          end
        end

        private

        # The pattern bit each pixel of a character shows, 0 for the first,
        # or -1 for the background.
        def lay_out_cell
          regs = @registers
          double = regs[25].anybits?(0x10)
          @dot = double ? 2 : 1
          @cell = double ? [regs[22] >> 4, 1].max : (regs[22] >> 4) + 1
          @layout = Array.new(@cell, -1) if @layout.length < @cell
          scroll = regs[25] & 0x0f
          load = (scroll + 1) % @cell
          @shift = (@cell - 1 - scroll) % @cell
          last_shown = (regs[22] & 0x0f) - (double ? 1 : 0)
          shown = last_shown >= @cell ? @cell : ((last_shown - load) % @cell) + 1
          shown = [shown, 8].min
          semigraphic = regs[25].anybits?(0x20)
          @cell.times { |pixel| @layout[pixel] = cell_bit(pixel, shown, semigraphic) }
        end

        def cell_bit(pixel, shown, semigraphic)
          return pixel if pixel < shown

          semigraphic ? shown - 1 : -1
        end

        def paint_text(line, char_row, char_line, frame)
          regs = @registers
          @screen = @display_start + (char_row * @stride)
          @attributes = @attribute_start + (char_row * @stride)
          tall = (regs[9] & 0x1f) > 15
          @set = tall ? (regs[28] & 0xc0) << 8 : (regs[28] & 0xe0) << 8
          @set_size = tall ? 0x2000 : 0x1000
          @char_size = tall ? 32 : 16
          @pattern_line = tall ? char_line : char_line & 0x0f
          @underline = char_line == (regs[29] & 0x1f)
          @blink_on = frame % (regs[24].anybits?(0x20) ? 32 : 16) < (regs[24].anybits?(0x20) ? 16 : 8)
          @cursor = cursor_shown?(char_line, frame) ? (regs[14] << 8) | regs[15] : -1
          each_cell(line) { |n| text_cell(n) }
        end

        def paint_bitmap(line, content, char_row)
          @bitmap = @display_start + (content * @stride)
          @attributes = @attribute_start + (char_row * @stride)
          each_cell(line) { |n| bitmap_cell(n) }
        end

        def text_cell(index)
          address = (@screen + index) & 0xffff
          attribute = @attributes_on ? @memory.fetch((@attributes + index) & 0xffff) : 0
          @pattern = text_pattern(@memory.fetch(address), attribute)
          reverse = attribute.anybits?(0x40) ^ (address == @cursor) ^ @screen_reverse
          foreground = @attributes_on ? attribute & 0x0f : @registers[26] >> 4
          colours(foreground, @registers[26] & 0x0f, reverse)
        end

        def text_pattern(code, attribute)
          return 0 if attribute.anybits?(0x10) && !@blink_on
          return 0xff if attribute.anybits?(0x20) && @underline
          return 0 if @gap_line

          set = @set + (attribute.anybits?(0x80) ? @set_size : 0)
          @memory.fetch((set + (code * @char_size) + @pattern_line) & 0xffff)
        end

        def bitmap_cell(index)
          @pattern = @gap_line ? 0 : @memory.fetch((@bitmap + index) & 0xffff)
          regs = @registers
          if @attributes_on
            attribute = @memory.fetch((@attributes + index) & 0xffff)
            colours(attribute & 0x0f, attribute >> 4, @screen_reverse)
          else
            colours(regs[26] >> 4, regs[26] & 0x0f, @screen_reverse)
          end
        end

        def colours(foreground, background, reverse)
          @foreground = reverse ? background : foreground
          @background = reverse ? foreground : background
        end

        # Paints the cells the display shows, one more when the line is
        # scrolled, each after the block sets its pattern and colours.
        def each_cell(line)
          count = @registers[1] + (@shift.positive? ? 1 : 0)
          right = @registers[1] * @cell
          index = 0
          while index < count
            yield index
            paint_cell(line, (index * @cell) - @shift, right)
            index += 1
          end
        end

        def paint_cell(line, left, right)
          gap = @registers[26] & 0x0f
          pixel = 0
          while pixel < @cell
            x_pos = left + pixel
            line.fill(pixel_colour(@layout[pixel], gap), x_pos * @dot, @dot) if x_pos >= 0 && x_pos < right
            pixel += 1
          end
        end

        def pixel_colour(bit, gap)
          return gap if bit.negative?

          @pattern.anybits?(0x80 >> bit) ? @foreground : @background
        end

        def cursor_shown?(char_line, frame)
          mode = (@registers[10] >> 5) & 3
          return false if mode == 1
          return false if mode == 2 && (frame % 16) >= 8
          return false if mode == 3 && (frame % 32) >= 16

          cursor_line?(char_line)
        end

        def cursor_line?(char_line)
          first = @registers[10] & 0x1f
          stop = @registers[11] & 0x1f
          return char_line >= first && char_line < stop if first < stop

          first > stop && (char_line >= first || char_line < stop)
        end
      end
    end
  end
end
