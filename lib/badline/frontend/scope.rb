# frozen_string_literal: true

module Badline
  module Frontend
    # An oscilloscope in a box: one channel of SIDHistory's samples, as
    # heard, with the trace held still on a rising edge. `box` is its left,
    # top, width and height, `span` how many samples fit its width and
    # `range` the swing that fills its height. The trace is centred on the
    # middle of the samples' range when `centred`, and on zero otherwise.
    class Scope
      def initialize(painter, box, span:, range:, centred: false)
        @painter = painter
        @left = box[0]
        @top = box[1]
        @width = box[2]
        @height = box[3]
        @span = span
        @range = range
        @centred = centred
        @points = Array.new((@width + 1) * 2, 0)
      end

      def draw(history, played, channel, rgb)
        @painter.box(@left, @top, @width, @height, SIDView::BOX)
        span = @span
        range = @range
        start = history.scope_start(played, span, channel)
        middle = @centred ? history.middle(start, span, channel) : 0
        centre = @top + (@height / 2)
        points = @points
        x = 0
        while x <= @width
          value = history.sample_at(start + (x * span / @width), channel) - middle
          points[x * 2] = @left + x
          points[(x * 2) + 1] = (centre - (value * (@height - 4) / range)).clamp(@top, @top + @height - 1)
          x += 1
        end
        @painter.polyline(points, rgb)
      end
    end
  end
end
