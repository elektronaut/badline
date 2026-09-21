# frozen_string_literal: true

require "badline/vic/border_mask"
require "badline/vic/color_patches"
require "badline/vic/graphics_mode"

module Badline
  class VIC < Cycleable
    # = VIC-II Sequencer
    #
    # Turns fetched graphics data into output pixels.
    class Sequencer
      DISPLAY_X_BOUNDS = [
        [135, 438].freeze,
        [128, 447].freeze
      ].freeze

      # The graphics window always spans the full 40 columns, ignoring CSEL.
      GFX_X_START = DISPLAY_X_BOUNDS[1][0]
      GFX_X_END = DISPLAY_X_BOUNDS[1][1] + 1

      # [left compare, right compare] for the border flip-flop per CSEL state.
      WINDOW_COMPARES = [
        [DISPLAY_X_BOUNDS[0][0], DISPLAY_X_BOUNDS[0][1] + 1].freeze,
        [GFX_X_START, GFX_X_END].freeze
      ].freeze

      BORDER_Y_BOUNDS = [
        [55, 247].freeze,
        [51, 251].freeze
      ].freeze

      MODES = GraphicsMode::MODES

      attr_reader :colors, :fg, :registers, :bank, :cur_colors,
                  :color_patches
      # The fg masks are shared frozen patterns assigned by reference, never
      # mutated in place.
      attr_accessor :cur_fg

      def initialize(width, registers, bank)
        @width = width
        @registers = registers
        @bank = bank
        @colors = Array.new(width, 0)
        @fg = Array.new(width, false)
        @border_mask = BorderMask.new(width)
        # Hot-path aliases: the pixel loops write coverage straight into the
        # mask's arrays.
        @border = @border_mask.mask
        @border_groups = @border_mask.groups
        @cur_colors = Array.new(8, 0)
        @cur_fg = GraphicsMode::NO_FG
        @prev_colors = Array.new(8, 0)
        @prev_fg = GraphicsMode::NO_FG
        @vertical_border = true
        @main_border = true
        @color_patches = ColorPatches.new(self)
        new_line(0)
      end

      # Reset the line buffers at the start of a rasterline.
      def new_line(line)
        @line = line
        @colors.fill(@registers.border)
        @fg.fill(false)
        @border_mask.reset
        @prev_colors.fill(@registers.background)
        @prev_fg = GraphicsMode::NO_FG
        @color_patches.clear
      end

      def apply_color_patches
        @color_patches.apply(@colors, @fg)
      end

      # The vertical border flip-flop is set on the bottom compare line and
      # reset on the top compare line when DEN is set. The compares run at
      # cycle 63 and at the left window edge (Bauer §3.9 rules 2-5), so
      # mid-frame RSEL/DEN toggles can open or close the border.
      def check_vertical_border(line = @line)
        top, bottom = BORDER_Y_BOUNDS[@registers.rsel? ? 1 : 0]
        @vertical_border = true if line == bottom
        @vertical_border = false if line == top && @registers.display_enabled?
      end

      def border_at?(pixel_x) = @border_mask.at?(pixel_x)

      # Snapshot the finished line so apply_border can restore the border
      # pixels sprites were composited over, keeping mid-line border splits.
      def snapshot_line = @border_mask.snapshot(@colors)

      # Repaint the border over the composited line, hiding the sprites.
      def apply_border = @border_mask.restore(@colors)

      def emit(screencode, color, col, cell, row)
        MODES[@registers.mode].decode(screencode, color, cell, row, self)
        output(col)
        roll
      end

      # In idle state the g-accesses read $3fff ($39ff with ECM) and the data
      # is displayed as if the video matrix supplied all-zero bits. The decode
      # is skipped while the vertical border is closed and cannot open on this
      # line, since no pixel of the group can be shown.
      def emit_idle(col)
        if idle_pixels_hidden?
          @cur_fg = GraphicsMode::NO_FG
        else
          GraphicsMode::IDLE.decode(self)
        end
        output(col)
        roll
      end

      private

      # While the vertical border is closed, the only line where it can open
      # mid-line is a top compare line with DEN set, so all others skip the
      # decode after two compares.
      def idle_pixels_hidden?
        return false unless @vertical_border
        return true unless @line == 51 || @line == 55

        top, = BORDER_Y_BOUNDS[@registers.rsel? ? 1 : 0]
        !(@line == top && @registers.display_enabled?)
      end

      # Write the 8-pixel group for a column into the line buffers. The main
      # border flip-flop only changes state in the groups containing the
      # window edge compares, so all other groups take a branch-free bulk
      # path: fully border or fully window.
      def output(col)
        x_pos = (col + 16) * 8
        win_lo, right_compare = WINDOW_COMPARES[@registers.csel? ? 1 : 0]

        if boundary_group?(x_pos, win_lo, right_compare)
          output_boundary(col, x_pos, win_lo, right_compare)
        elsif @main_border || @vertical_border
          output_border(x_pos)
        else
          output_window(col, x_pos)
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

      def output_window(col, x_pos)
        in_gfx = x_pos >= GFX_X_START && x_pos < GFX_X_END
        @border_groups[x_pos >> 3] = BorderMask::NONE

        if @registers.xscroll.zero?
          @colors[x_pos, 8] = @cur_colors
          if in_gfx
            @fg[x_pos, 8] = @cur_fg
          else
            @fg.fill(false, x_pos, 8)
          end
        else
          output_window_shifted(col, x_pos, in_gfx)
        end
      end

      def output_window_shifted(col, x_pos, in_gfx)
        shift = @registers.xscroll
        keep = 8 - shift

        @colors[x_pos + shift, keep] = @cur_colors[0, keep]
        if col.positive? # the left column only exists from column 1 on
          @colors[x_pos, shift] = @prev_colors[keep, shift]
        else
          @colors.fill(@registers.background, x_pos, shift)
        end
        output_shifted_fg(col, x_pos, in_gfx, shift, keep)
      end

      def output_shifted_fg(col, x_pos, in_gfx, shift, keep)
        return @fg.fill(false, x_pos, 8) unless in_gfx

        @fg[x_pos + shift, keep] = @cur_fg[0, keep]
        if col.positive?
          @fg[x_pos, shift] = @prev_fg[keep, shift]
        else
          @fg.fill(false, x_pos, shift)
        end
      end

      # Slow path for the groups where the border flip-flop can change state.
      def output_boundary(col, x_pos, win_lo, right_compare)
        shift = @registers.xscroll
        bg = @registers.background
        bleed = col.positive?
        border = @registers.border
        @border_groups[x_pos >> 3] = BorderMask::MIXED

        i = 0
        while i < 8
          src = i - shift
          if src >= 0
            pixel = @cur_colors[src]
            mask = @cur_fg[src]
          elsif bleed
            pixel = @prev_colors[8 + src]
            mask = @prev_fg[8 + src]
          else
            pixel = bg
            mask = false
          end
          x = x_pos + i
          shown = pixel_shown?(x, win_lo, right_compare)
          @colors[x] = shown ? pixel : border
          @border[x] = !shown
          @fg[x] = x >= GFX_X_START && x < GFX_X_END ? mask : false
          i += 1
        end
      end

      def pixel_shown?(pixel_x, left_compare, right_compare)
        @main_border = true if pixel_x == right_compare
        if pixel_x == left_compare
          check_vertical_border
          @main_border = false unless @vertical_border
        end
        !(@main_border || @vertical_border)
      end

      def roll
        @prev_colors, @cur_colors = @cur_colors, @prev_colors
        @prev_fg, @cur_fg = @cur_fg, @prev_fg
      end
    end
  end
end
