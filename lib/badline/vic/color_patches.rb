# frozen_string_literal: true

module Badline
  class VIC
    # A mid-line color register write becomes visible one pixel into the
    # column emitted the cycle after the write. That emit paints the whole
    # column with the new color, so the boundary pixel is patched back to
    # the old one before the line is finished. On the 8565 the boundary
    # pixel shows light grey instead, the grey dot, whatever the old and new
    # colors are.
    class ColorPatches
      def initialize(sequencer, grey_dots: false)
        @sequencer = sequencer
        @grey_dots = grey_dots
        @patches = []
      end

      def clear = @patches.clear

      # Each patch as its four numbers: the boundary pixel, the register,
      # the old colour and the new.
      def save_state(out)
        out.int(@patches.length)
        @patches.each { |patch| out.ints(patch) }
      end

      def load_state(input)
        @patches.replace(Array.new(input.int) { input.ints })
      end

      def log(reg, old, value, boundary_x)
        @patches << [boundary_x, reg, @grey_dots ? GREY_DOT : old & 0x0f, value & 0x0f]
      end

      def apply(colors, fg_mask)
        @patches.each do |(x, reg, old, value)|
          border = @sequencer.border_at?(x)
          if reg == 0x20
            colors[x] = old if border
          elsif !border && !fg_mask[x] && colors[x] == value
            colors[x] = old
          end
        end
      end
    end
  end
end
