# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # A mid-line color register write becomes visible one pixel into the
    # column emitted the cycle after the write. That emit paints the whole
    # column with the new color, so the boundary pixel is patched back to
    # the old one before the line is finished.
    class ColorPatches
      def initialize(sequencer)
        @sequencer = sequencer
        @patches = []
      end

      def clear = @patches.clear

      def log(reg, old, value, boundary_x)
        @patches << [boundary_x, reg, old & 0x0f, value & 0x0f]
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
