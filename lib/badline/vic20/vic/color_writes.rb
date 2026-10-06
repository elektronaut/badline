# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # Colour register writes, $900E and $900F, which Vic20::VIC includes.
      # A write the CPU makes in one cycle shows from the second pixel of
      # the group the VIC draws in the next, and a change of $900F bit 3
      # (reverse mode) from the fourth: the first pixel, or the first
      # three, keep the old value.
      module ColorWrites
        private

        def set_colors(background, border, auxiliary, reverse)
          @background = background
          @border = border
          @auxiliary = auxiliary
          @reverse = reverse
          @colors_changed = true
        end

        # Once the cycle a write landed in has drawn, the old values are
        # the new ones.
        def sync_colors
          @old_background = @background
          @old_border = @border
          @old_auxiliary = @auxiliary
          @old_reverse = @reverse
          @colors_changed = false
        end

        # A character's group in the cycle a write lands: the first pixel
        # in the old colours and reverse mode, the next two in the new
        # colours and the old reverse mode, the last in the new.
        def draw_split_group(pos, bits)
          line = @line
          background = @background
          border = @border
          auxiliary = @auxiliary
          reverse = @reverse
          use_colors(@old_background, @old_border, @old_auxiliary)
          first = draw_in_mode(pos, bits, @old_reverse)
          use_colors(background, border, auxiliary)
          draw_in_mode(pos, bits, @old_reverse)
          second = line[pos + 1]
          third = line[pos + 2]
          draw_in_mode(pos, bits, reverse)
          line[pos] = first
          line[pos + 1] = second
          line[pos + 2] = third
        end

        def use_colors(background, border, auxiliary)
          @background = background
          @border = border
          @auxiliary = auxiliary
        end

        # Draws the group with +reverse+ as the reverse mode, and returns
        # its first pixel.
        def draw_in_mode(pos, bits, reverse)
          @reverse = reverse
          color = @pattern_color
          if color < 8
            draw_hires(pos, reverse == 1 ? bits ^ 0x0f : bits, color)
          else
            draw_multicolor(pos, bits, color & 0x07)
          end
          @line[pos]
        end
      end
    end
  end
end
