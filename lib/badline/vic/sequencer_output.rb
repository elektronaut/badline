# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    class Sequencer
      # Writes a column's 8-pixel group into the line buffers, through the
      # main border flip-flop and XSCROLL.
      module Output
        private

        # Write the 8-pixel group for a column into the line buffers. The main
        # border flip-flop only changes state in the groups containing the
        # window edge compares, so all other groups take a branch-free bulk
        # path: fully border or fully window.
        def output(col, shift)
          x_pos = (col + 16) * 8
          win_lo, right_compare = WINDOW_COMPARES[@registers.csel? ? 1 : 0]

          if boundary_group?(x_pos, win_lo, right_compare)
            output_boundary(x_pos, win_lo, right_compare, shift)
          elsif @main_border
            output_border(x_pos)
          else
            output_window(x_pos, shift)
          end
        end

        # True if the group contains a window edge, where the main border
        # flip-flop can change state.
        def boundary_group?(x_pos, win_lo, right_compare)
          lo_delta = win_lo - x_pos
          hi_delta = right_compare - x_pos
          (lo_delta >= 0 && lo_delta < 8) || (hi_delta >= 0 && hi_delta < 8)
        end

        def output_border(x_pos)
          @colors.fill(@registers.border, x_pos, 8)
          @border_groups[x_pos >> 3] = BorderMask::FULL
          @fg.fill(false, x_pos, 8)
        end

        def output_window(x_pos, shift)
          in_gfx = x_pos >= GFX_X_START && x_pos < GFX_X_END
          @border_groups[x_pos >> 3] = BorderMask::NONE

          if shift.zero?
            @colors[x_pos, 8] = @cur_colors
            if in_gfx
              @fg[x_pos, 8] = @cur_fg
            else
              @fg.fill(false, x_pos, 8)
            end
          else
            output_window_shifted(x_pos, in_gfx, shift)
          end
        end

        def output_window_shifted(x_pos, in_gfx, shift)
          keep = 8 - shift

          copy(@cur_colors, 0, @colors, x_pos + shift, keep)
          copy(@prev_colors, keep, @colors, x_pos, shift)
          output_shifted_fg(x_pos, in_gfx, shift, keep)
        end

        def output_shifted_fg(x_pos, in_gfx, shift, keep)
          return @fg.fill(false, x_pos, 8) unless in_gfx

          copy(@cur_fg, 0, @fg, x_pos + shift, keep)
          copy(@prev_fg, keep, @fg, x_pos, shift)
        end

        def copy(src, from, dest, to, count)
          i = 0
          while i < count
            dest[to + i] = src[from + i]
            i += 1
          end
        end

        # Slow path for the groups where the border flip-flop can change state.
        def output_boundary(x_pos, win_lo, right_compare, shift)
          border = @registers.border
          @border_groups[x_pos >> 3] = BorderMask::MIXED

          i = 0
          while i < 8
            src = i - shift
            if src >= 0
              pixel = @cur_colors[src]
              mask = @cur_fg[src]
            else
              pixel = @prev_colors[8 + src]
              mask = @prev_fg[8 + src]
            end
            x = x_pos + i
            shown = pixel_shown?(x, win_lo, right_compare)
            @colors[x] = shown ? pixel : border
            @border[x] = !shown
            @fg[x] = x >= GFX_X_START && x < GFX_X_END ? mask : false
            i += 1
          end
        end
      end
    end
  end
end
