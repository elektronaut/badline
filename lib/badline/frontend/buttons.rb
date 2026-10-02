# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's buttons: each is drawn where it goes on every frame,
    # and remembers its place, so a click finds the action under it. The
    # one under the pointer lights up, and one that's on is drawn reversed.
    class Buttons
      PAD = 2
      HEIGHT = Painter::GLYPH + (PAD * 2)

      def initialize(painter)
        @painter = painter
        @lefts = []
        @tops = []
        @widths = []
        @heights = []
        @actions = []
        @pointer_x = -1
        @pointer_y = -1
      end

      def forget
        @lefts.clear
        @tops.clear
        @widths.clear
        @heights.clear
        @actions.clear
      end

      def point(left, top)
        @pointer_x = left
        @pointer_y = top
      end

      # Draws a button labelled `label` with its top left at `left`, `top`,
      # and returns its width.
      def text(left, top, label, action, on: false)
        width = Painter.width(label) + (PAD * 2)
        place(left, top, width, HEIGHT, action)
        @painter.box(left, top, width, HEIGHT, SIDView::TEXT) if on
        @painter.text(left + PAD, top + PAD, label, on ? PlayerWindow::BACKGROUND : color(@actions.size - 1))
        width
      end

      # Draws an icon button `scale` times the size of a glyph, and returns
      # its width.
      def icon(left, top, name, action, scale: 1)
        size = (Painter::GLYPH * scale) + (PAD * 2)
        place(left, top, size, size, action)
        @painter.icon(name, left + PAD, top + PAD, color(@actions.size - 1), scale:)
        size
      end

      # Makes a box drawn elsewhere clickable, such as the bar showing the
      # time played.
      def area(box, action)
        place(box[0], box[1], box[2], box[3], action)
      end

      # The action of the button at `left`, `top`, or nil.
      def action_at(left, top)
        index = 0
        while index < @actions.size
          return @actions[index] if inside?(index, left, top)

          index += 1
        end
        nil
      end

      private

      def place(left, top, width, height, action)
        @lefts << left
        @tops << top
        @widths << width
        @heights << height
        @actions << action
      end

      def color(index) = inside?(index, @pointer_x, @pointer_y) ? SIDView::BRIGHT : SIDView::TEXT

      def inside?(index, left, top)
        left >= @lefts[index] && left < @lefts[index] + @widths[index] &&
          top >= @tops[index] && top < @tops[index] + @heights[index]
      end
    end
  end
end
