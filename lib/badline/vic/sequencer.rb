# frozen_string_literal: true

require "badline/vic/border_mask"
require "badline/vic/color_patches"
require "badline/vic/graphics_mode"
require "badline/vic/graphics_shifter"
require "badline/vic/sequencer_output"

module Badline
  class VIC < Cycleable
    # = VIC-II Sequencer
    #
    # Turns fetched graphics data into output pixels.
    class Sequencer
      include Output

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
        @vertical_armed = true
        @main_border = true
        @color_patches = ColorPatches.new(self)
        @shifter = GraphicsShifter.new(registers)
        @xscroll = 0
        @last_shift = 0
        @last_mode = 0
        @settling = false
        @ring_data = Array.new(4, 0)
        @ring_char = Array.new(4, 0)
        @ring_color = Array.new(4, 1)
        @prev_fresh = false
        @check = true
        new_line(0)
      end

      # Reset the line buffers at the start of a rasterline.
      def new_line(line)
        @line = line
        @left_vertical_border = nil
        @first_csel = @registers.csel?
        @colors.fill(@registers.border)
        @fg.fill(false)
        @border_mask.reset
        @prev_colors.fill(@registers.background)
        @prev_fg = GraphicsMode::NO_FG
        @prev_fresh = false
        @check = true
        @color_patches.clear
      end

      # The load point for the next group's byte: XSCROLL as a g-access
      # column with the border open sees it, a column before the group that
      # uses it (VICE x64sc `xscroll_pipe`).
      def latch_xscroll(xscroll = @registers.xscroll)
        return if xscroll == @xscroll

        @xscroll = xscroll
        @check = true
      end

      # A write to a register the painted colours depend on: the byte kept
      # from the previous group is painted again before its pixels are shown.
      def colors_changed!
        @prev_fresh = false
        @check = true
      end

      def apply_color_patches
        @color_patches.apply(@colors, @fg)
      end

      # The vertical border compares run in every cycle of their line (VICE
      # x64sc). The top one resets the flip-flop at once when DEN is set. The
      # bottom one only arms it, and the armed state takes hold at the line's
      # first cycle and at the left window edge (Bauer §3.9 rules 2-5). The
      # VIC calls this after each $d011 write.
      def compare_vertical_border(line)
        top, bottom = BORDER_Y_BOUNDS[@registers.rsel? ? 1 : 0]
        @vertical_armed = true if line == bottom
        @vertical_armed = @vertical_border = false if line == top && @registers.display_enabled?
      end

      # The line's first cycle, Bauer's cycle 1, which is the last column of
      # the line before it.
      def start_vertical_border(line)
        compare_vertical_border(line)
        @vertical_border = @vertical_armed
      end

      # The 40-column left compare, a column before the column that draws its
      # pixel. The 38-column one runs in the drawing column.
      def left_compare_vertical_border
        @left_vertical_border = start_vertical_border(@line) if @registers.csel?
      end

      def border_at?(pixel_x) = @border_mask.at?(pixel_x)

      # True while the vertical border flip-flop is set and stays set for the
      # rest of the line: it can only clear mid-line on a top compare line
      # with DEN set.
      def vertical_closed?
        return false unless @vertical_border
        return true unless @line == 51 || @line == 55

        top, = BORDER_Y_BOUNDS[@registers.rsel? ? 1 : 0]
        !(@line == top && @registers.display_enabled?)
      end

      # Snapshot the finished line so apply_border can restore the border
      # pixels sprites were composited over, keeping mid-line border splits.
      def snapshot_line = @border_mask.snapshot(@colors)

      # Repaint the border over the composited line, hiding the sprites.
      def apply_border = @border_mask.restore(@colors)

      # The g-accesses the VIC hands over, as a ring the column's slot
      # indexes: the byte read, the screen byte and the colour nibble. The
      # slot before is the byte the previous group loaded.
      attr_reader :ring_data, :ring_char, :ring_color

      # Paints the byte in the slot through the current mode. An idle access
      # latches 0/0 and one that made no access passes on zero data with the
      # kept values; under a closed border neither has foreground. A group
      # where the mode or the load point changes, and the one after it, run
      # the shift register pixel by pixel.
      def emit(slot, col, display)
        mode = @registers.mode
        return emit_checked(slot, col, display, mode) if @check || mode != @last_mode

        paint_slot(slot, mode, display)
        output(col, @last_shift)
        roll
      end

      private

      # After a mode, XSCROLL or colour change: groups paint whole bytes
      # again once the change has settled, and run pixel by pixel until then.
      def emit_checked(slot, col, display, mode)
        shift = @xscroll
        if mode == @last_mode && shift == @last_shift && !@settling
          emit_settled(slot, col, display, mode, shift)
        else
          emit_pixels(slot, col, mode, shift, !display && border_hidden?)
          @settling = mode != @last_mode || shift != @last_shift
          @last_mode = mode
          @last_shift = shift
        end
      end

      def emit_settled(slot, col, display, mode, shift)
        repaint_previous(mode, (slot - 1) & 3) unless @prev_fresh || shift.zero?
        paint_slot(slot, mode, display)
        output(col, shift)
        roll
        @prev_fresh = true
        @check = false
      end

      def paint_slot(slot, mode, display)
        if !display && border_hidden?
          @cur_fg = GraphicsMode::NO_FG
        else
          MODES[mode].paint(@ring_data[slot], @ring_char[slot], @ring_color[slot], self)
        end
      end

      def repaint_previous(mode, slot)
        roll
        MODES[mode].paint(@ring_data[slot], @ring_char[slot], @ring_color[slot], self)
        roll
      end

      def emit_pixels(slot, col, mode, shift, hidden)
        prime_shifter((slot - 1) & 3) unless @settling
        @shifter.draw(hidden ? 0 : @ring_data[slot], @ring_char[slot], @ring_color[slot], shift, mode)
        @cur_colors[0, 8] = @shifter.colors
        @cur_fg = @shifter.fg
        output(col, 0)
        @prev_fresh = false
        @check = true
      end

      # Picks up from a group that painted whole bytes.
      def prime_shifter(slot)
        @shifter.prime(@ring_data[slot], @ring_char[slot], @ring_color[slot], @last_shift, @last_mode)
      end

      # The group is border throughout when the main flip-flop is set and the
      # vertical one keeps it from clearing.
      def border_hidden? = @main_border && vertical_closed?

      def pixel_shown?(pixel_x, left_compare, right_compare)
        @main_border = true if pixel_x == right_compare
        @main_border = false if pixel_x == left_compare && !left_vertical_border
        !@main_border
      end

      def left_vertical_border
        @left_vertical_border.nil? ? start_vertical_border(@line) : @left_vertical_border
      end

      def roll
        @prev_colors, @cur_colors = @cur_colors, @prev_colors
        @prev_fg, @cur_fg = @cur_fg, @prev_fg
        nil
      end
    end
  end
end
