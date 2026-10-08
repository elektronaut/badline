# frozen_string_literal: true

module Badline
  class C128
    class VDC
      # Paints the VDC's scan lines into its display, one line at a time,
      # from the registers as they stand when the line ends. Each pixel of
      # the display is one period of the 16 MHz dot clock, so a pixel of
      # the double-width mode, R25 bit 4, covers two. Window paints the
      # characters of the lines in the displayed rows.
      #
      # The horizontal counter that R2, R34 and R35 compare runs
      # COUNTER_LEAD characters ahead of the character on screen: the soci
      # testprogs set R34 = 6 and R35 = R1 + 8 for one character of border
      # either side of the display, as test01.jpg shows on a real machine.
      # The display holds each line from the end of the horizontal sync, R2
      # plus R3 bits 0-3 on that counter, as a monitor shows it, and its
      # rows from the end of the vertical sync, which starts R7 - 1 rows
      # into the frame (the Programmer's Reference Guide counts R7 "plus 1")
      # and lasts R3 bits 4-7 lines, or 16 for 0. The vertical sync and the
      # characters outside R34 up to R35 are black, and the rest of the
      # border is the background colour, R26 bits 0-3.
      #
      # The display is as wide as a line and as high as a frame, up to
      # MAX_WIDTH by MAX_HEIGHT; lines and pixels past those are left out.
      class Painter
        COUNTER_LEAD = 7
        MIN_LINE_DOTS = 128
        MAX_WIDTH = 1024
        MAX_HEIGHT = 320

        attr_reader :display, :width, :height, :dirty_lines

        def initialize(registers, memory)
          @registers = registers
          @window = Window.new(registers, memory)
          @line = Array.new(MAX_WIDTH, 0)
          resize(MIN_LINE_DOTS, 1)
        end

        # Latches the start addresses, and starts the display again when
        # the frame's size has changed.
        def begin_frame(line_dots, frame_lines)
          @window.latch_starts
          width = line_dots.clamp(MIN_LINE_DOTS, MAX_WIDTH)
          height = frame_lines.clamp(1, MAX_HEIGHT)
          resize(width, height) if width != @width || height != @height
        end

        # The [left, top, width, height] of the display a monitor shows:
        # all of a line but the horizontal sync, all of a frame but the
        # vertical sync.
        def crop(line_dots, frame_lines, sync_lines)
          regs = @registers
          shown = line_dots - ((regs[3] & 0x0f) * VDC.char_dots(regs))
          [0, 0, shown.clamp(1, @width), (frame_lines - sync_lines).clamp(1, @height)]
        end

        # The display's size and the window's start addresses. The display
        # starts again cleared, to be painted while the VDC renders.
        def save_state(out)
          out.int(@width).int(@height)
          @window.save_state(out)
        end

        def load_state(input)
          resize(input.int, input.int)
          @window.load_state(input)
        end

        def clear_dirty_lines!
          @dirty_lines.fill(false)
        end

        def clear!
          @display.fill(0)
          @dirty_lines.fill(true)
        end

        # Paints the line `line_y` lines after the vertical sync ends.
        # `row` and `row_line` place it in the frame's character rows, or
        # `row` is -1 in the adjust lines after the last row, and `sync` is
        # set in the vertical sync. `frame` counts frames for the blinking.
        def paint(line_y, row, row_line, sync, frame)
          return if line_y >= @height

          regs = @registers
          char_dots = VDC.char_dots(regs)
          line_dots = (regs[0] + 1) * char_dots
          @line = Array.new(line_dots, 0) if @line.length < line_dots
          line = @line
          line.fill(sync ? 0 : regs[26] & 0x0f, 0, line_dots)
          unless sync
            @window.paint(line, row, row_line, frame) if row >= 0 && row < regs[6]
            blank(line, line_dots, char_dots)
          end
          copy_out(line, line_y, line_dots, char_dots)
        end

        private

        def resize(width, height)
          @width = width
          @height = height
          @display = Array.new(width * height, 0)
          @dirty_lines = Array.new(height, true)
        end

        def sync_end_chars(regs) = regs[2] + (regs[3] & 0x0f) - COUNTER_LEAD

        def blank(line, line_dots, char_dots)
          first = @registers[34]
          last = @registers[35]
          return if first == last

          total = line_dots / char_dots
          char = 0
          while char < total
            counter = (char + COUNTER_LEAD) % total
            line.fill(0, char * char_dots, char_dots) unless enabled?(counter, first, last)
            char += 1
          end
        end

        def enabled?(counter, first, last)
          return counter >= first && counter < last if first < last

          counter >= first || counter < last
        end

        def copy_out(line, line_y, line_dots, char_dots)
          origin = (sync_end_chars(@registers) * char_dots) % line_dots
          base = line_y * @width
          head = [line_dots - origin, @width].min
          @display[base, head] = line[origin, head]
          tail = [@width - head, origin].min
          @display[base + head, tail] = line[0, tail] if tail.positive?
          @dirty_lines[line_y] = true
        end
      end
    end
  end
end
