# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # Border coverage per 8-pixel group, tracked as the sequencer outputs
    # a line.
    #
    # The border is repainted over composited sprites from a snapshot of
    # the finished line, which keeps mid-line border color splits intact.
    class BorderMask
      FULL  = 0
      NONE  = 1
      MIXED = 2

      # The group table and per-pixel mask are exposed so the sequencer's
      # pixel loops can write them without a method call per column.
      attr_reader :groups, :mask

      def initialize(width)
        @width = width
        @groups = Array.new(width / 8, FULL)
        @mask = Array.new(width, true)
        @snapshot = Array.new(width, 0)
      end

      def reset
        @groups.fill(FULL)
      end

      def at?(pixel_x)
        case @groups[pixel_x >> 3]
        when FULL then true
        when MIXED then @mask[pixel_x]
        else false
        end
      end

      def snapshot(colors)
        @snapshot[0, @width] = colors
      end

      def restore(colors)
        group = 0
        while group < @groups.length
          case @groups[group]
          when FULL then group = restore_full(colors, group)
          when MIXED then restore_mixed(colors, group * 8)
          end
          group += 1
        end
      end

      private

      # Copies a run of full-border groups in one splice and returns its
      # last group.
      def restore_full(colors, first)
        last = first
        last += 1 while @groups[last + 1] == FULL
        x_pos = first * 8
        length = (last - first + 1) * 8
        colors[x_pos, length] = @snapshot[x_pos, length]
        last
      end

      def restore_mixed(colors, x_pos)
        i = 0
        while i < 8
          x = x_pos + i
          colors[x] = @snapshot[x] if @mask[x]
          i += 1
        end
      end
    end
  end
end
