# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's buttons: each is drawn where it goes on every frame,
    # and remembers its place, so a click finds the action under it. The
    # one under the pointer lights up, and one that's on is drawn reversed.
    # They take the player's colours unless given others: the text, the text
    # under the pointer, the background and, if any, a fill behind each
    # button.
    class Buttons
      PAD = 2
      HEIGHT = Painter::GLYPH + (PAD * 2)

      def initialize(painter, colors = [SIDView::TEXT, SIDView::BRIGHT, PlayerScreen::BACKGROUND])
        @painter = painter
        @text = colors[0]
        @bright = colors[1]
        @back = colors[2]
        @fill = colors.size > 3 ? colors[3] : -1
        @lefts = []
        @tops = []
        @widths = []
        @heights = []
        @actions = []
        @focusable = []
        @toggles = {}
        @pointer_x = -1
        @pointer_y = -1
        @focus = nil
      end

      # The action of the button the keys have moved to, which lights up as
      # the one under the pointer does, or nil.
      attr_accessor :focus

      def forget
        @lefts.clear
        @tops.clear
        @widths.clear
        @heights.clear
        @actions.clear
        @focusable.clear
        @toggles.clear
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
        @painter.box(left, top, width, HEIGHT, @fill) if !on && @fill >= 0
        @painter.box(left, top, width, HEIGHT, action == @focus ? @bright : @text) if on
        @painter.text(left + PAD, top + PAD, label, on ? @back : color(@actions.size - 1))
        width
      end

      # Draws a button as #text does, without the fill.
      def plain(left, top, label, action, on: false)
        fill = @fill
        @fill = -1
        width = text(left, top, label, action, on:)
        @fill = fill
        width
      end

      # Draws a button as wide as `box`, its left and top and width, with
      # `label` at its left and `value`, if any, at its right, as a menu's
      # row.
      def row(box, label, action, value = "")
        left = box[0]
        top = box[1]
        width = box[2]
        place(left, top, width, HEIGHT, action)
        @painter.box(left, top, width, HEIGHT, @fill) if @fill >= 0
        color = color(@actions.size - 1)
        @painter.text(left + PAD, top + PAD, label, color)
        @painter.text(left + width - PAD - Painter.width(value), top + PAD, value, color) unless value.empty?
      end

      # Draws a row as #row does, with its choices at its right, `choices`
      # holding their labels, their actions and the index of the one on.
      # A click picks a choice, and pressing the row, `action`, picks the
      # next, which #resolve gives.
      def toggle(box, label, action, choices)
        row(box, label, action)
        labels = choices[0]
        @toggles[action] = choices[1][(choices[2] + 1) % labels.size]
        right = box[0] + box[2] - PAD
        index = labels.size - 1
        while index >= 0
          width = Painter.width(labels[index]) + (PAD * 2)
          right -= width
          choice(right, box[1], labels[index], choices[1][index], index == choices[2])
          right -= 2
          index -= 1
        end
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

      # The action of the button at `left`, `top`, or nil: a toggle's
      # choice before the row it sits on.
      def action_at(left, top)
        found = nil
        index = 0
        while index < @actions.size
          if inside?(index, left, top)
            return @actions[index] unless @focusable[index]

            found ||= @actions[index]
          end
          index += 1
        end
        found
      end

      # Moves the focus `delta` buttons on, among those drawn from the
      # `first` on, stopping at either end.
      def shift(delta, first)
        return if @actions.size <= first

        focusable = []
        (first...@actions.size).each { |index| focusable << @actions[index] if @focusable[index] }
        return if focusable.empty?

        from = focusable.index(@focus)
        @focus = focusable[from.nil? ? 0 : (from + delta).clamp(0, focusable.size - 1)]
      end

      # The action pressing a button stands for: for a toggle's row, its
      # next choice's.
      def resolve(action) = @toggles.fetch(action, action)

      # The action of the button drawn `index`th, or nil.
      def action(index) = @actions[index]

      private

      def place(left, top, width, height, action)
        @lefts << left
        @tops << top
        @widths << width
        @heights << height
        @actions << action
        @focusable << true
      end

      # A choice of a toggle, which a click picks but the keys pass by.
      def choice(left, top, label, action, on)
        width = Painter.width(label) + (PAD * 2)
        place(left, top, width, HEIGHT, action)
        @focusable[-1] = false
        @painter.box(left, top, width, HEIGHT, @text) if on
        @painter.text(left + PAD, top + PAD, label, on ? @back : color(@actions.size - 1))
      end

      def color(index) = inside?(index, @pointer_x, @pointer_y) || @actions[index] == @focus ? @bright : @text

      def inside?(index, left, top)
        left >= @lefts[index] && left < @lefts[index] + @widths[index] &&
          top >= @tops[index] && top < @tops[index] + @heights[index]
      end
    end
  end
end
