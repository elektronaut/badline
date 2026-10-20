# frozen_string_literal: true

module Badline
  module Chips
    class VICI
      # The light pen input, the line the VIC-20 shares with the joystick's
      # fire button, and the position a falling edge on it latches into
      # $9006 and $9007.
      #
      # $9006 reads 2h + 1, where h is the edge's column plus two, wrapping
      # at the line's end, and $9007 bits 8-1 of the raster count in the
      # cycle after the edge. Around the cycle where the count turns to 0
      # the latch reads otherwise:
      #
      # - An edge from 8 cycles before that cycle to 1 after it latches as
      #   an edge in the cycle after it would, with $9007 at 0, but for an
      #   edge 2 cycles before it, which latches an even $9006, one less.
      # - Before that, an edge latches nothing while the count read its
      #   last value of the frame in the cycle before the edge: line 311 on
      #   the 6561, and 261, past the last line, on the 6560.
      module LightPen
        # Where the window around the count's turn to 0 starts and ends,
        # in cycles from that turn, and the edge in it that latches an even
        # $9006.
        WRAP_WINDOW = (-8..1)
        WRAP_EVEN = -2

        # The pen's line, low while the pen sees the beam or fire is held.
        def lightpen_level(high)
          low = !high
          return if low == @pen_low

          @pen_low = low
          pen_fell if low
        end

        private

        def power_on_pen!
          @pen_x = @pen_y = 0
          @pen_low = false
        end

        def pen_fell
          line = @rasterline
          column = @column
          from_wrap = cycles_from_wrap(line, column)
          if WRAP_WINDOW.cover?(from_wrap)
            latch_pen(@frame_wrap + 1, 0, from_wrap == WRAP_EVEN)
          elsif !pen_blocked?(line, column)
            next_column = column + 1
            if next_column == @cycles_per_line
              next_column = 0
              line = line == @frame_lines - 1 ? 0 : line + 1
            end
            latch_pen(column, count_at(line, next_column) >> 1, false)
          end
        end

        # How many cycles the beam is past the cycle where the count turns
        # to 0, negative before it. On the 6561 the count turns as the
        # frame starts, so the frame's first cycles are past it.
        def cycles_from_wrap(line, column)
          position = (line * @cycles_per_line) + column
          return position if position < 2 && @frame_wrap == @cycles_per_line

          position - ((@frame_lines - 1) * @cycles_per_line) - @frame_wrap
        end

        # Whether the count read its last value of the frame in the cycle
        # before this one.
        def pen_blocked?(line, column)
          column -= 1
          if column.negative?
            column = @cycles_per_line - 1
            line = line.zero? ? @frame_lines - 1 : line - 1
          end
          last = @frame_wrap > @count_column ? @frame_lines : @frame_lines - 1
          count_at(line, column) == last
        end

        def latch_pen(column, count, even)
          @pen_x = (2 * ((column + 2) % @cycles_per_line)) + (even ? 0 : 1)
          @pen_y = count
        end
      end
    end
  end
end
