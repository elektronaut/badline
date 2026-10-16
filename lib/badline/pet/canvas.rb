# frozen_string_literal: true

module Badline
  class PET
    # The picture a front end shows, a palette index a dot: 0 for black and
    # 1 for the lit phosphor. The video paints it eight dots at a time, one
    # character ROM row, and leaves alone the dots that would not change:
    # each four dots remember the row last painted from them, and a
    # painting that overlaps theirs from elsewhere makes them forget it.
    #
    # Each line keeps the span its last painting covered. When a line's
    # span changes, the dots it covered before and doesn't now go black.
    class Canvas
      # Black and the green of a P1 phosphor, as the VICE testbench's
      # references draw them.
      PALETTE = [0x000000, 0x41ff00].freeze

      # The eight dots of each ROM row, the leftmost in bit 7.
      DOTS = Array.new(256) { |bits| Array.new(8) { |dot| (bits >> (7 - dot)) & 1 } }.freeze

      attr_reader :display, :width, :height, :dirty_lines

      # Nothing paints within +margin+ dots of either side.
      def initialize(width, height, margin: 0)
        @first = margin
        @last = width - 8 - margin
        @width = width
        @height = height
        @display = Array.new(width * height, 0)
        @dirty_lines = Array.new(height, true)
        @slot_width = width >> 2
        @painted = Array.new(@slot_width * height, 0)
        @span_from = Array.new(height, 0)
        @span_to = Array.new(height, 0)
      end

      def palette = PALETTE

      def clear_dirty_lines!
        @dirty_lines.fill(false)
      end

      # Paints `bits` on `line` from dot `column` on, if they fit.
      def paint(column, line, bits)
        return if column < @first || column > @last

        slot = (line * @slot_width) + (column >> 2)
        return if @painted[slot] == bits

        @painted[slot] = bits
        @painted[slot - 1] = -1 if slot.positive?
        @painted[slot + 1] = -1 if slot + 1 < @painted.length
        @display[(line * @width) + column, 8] = DOTS[bits]
        @dirty_lines[line] = true
      end

      # Sets `line`'s span to the dots from `from` up to `to`, none if `to`
      # isn't past `from`, and blacks out what its last one covered beyond
      # it.
      def span(line, from, to)
        from = from.clamp(0, @width)
        to = to.clamp(0, @width)
        from = to = 0 if to <= from
        old_from = @span_from[line]
        old_to = @span_to[line]
        return if from == old_from && to == old_to

        blank(line, old_from, [from, old_to].min) if old_from < from
        blank(line, [to, old_from].max, old_to) if old_to > to
        @span_from[line] = from
        @span_to[line] = to
      end

      # Blacks out every dot, as at power on.
      def clear!
        @display.fill(0)
        @painted.fill(0)
        @span_from.fill(0)
        @span_to.fill(0)
        @dirty_lines.fill(true)
      end

      private

      def blank(line, from, to)
        return if to <= from

        @display.fill(0, (line * @width) + from, to - from)
        first = (line * @slot_width) + (from >> 2)
        @painted.fill(0, first, ((to + 3) >> 2) - (from >> 2))
        @painted[first - 1] = -1 if from >= 4
        @dirty_lines[line] = true
      end
    end
  end
end
