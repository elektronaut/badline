# frozen_string_literal: true

module Badline
  module Frontend
    # The bottom of the SID player's window: how far the subtune has played,
    # on a bar a click seeks along, and the buttons that pause and step
    # through the queue's tunes and the tune's subtunes and turn the queue's
    # modes on and off.
    class PlayerFooter
      HEIGHT = 44
      WIDTH = PlayerHeader::WIDTH
      CLOCK = "00:00 / 00:00"
      BAR_LEFT = 16
      BAR_WIDTH = WIDTH - 32 - (CLOCK.length * Painter::GLYPH) - 8
      TOGGLES = ["SHUFFLE", "LOOP", "ALL SUBTUNES"].freeze
      TOGGLE_ACTIONS = %i[shuffle loop all_subtunes].freeze
      TOGGLE_NOTES = ["shuffle", "loop", "all subtunes"].freeze

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
      end

      def draw(state, top)
        draw_progress(state, top + 4)
        row = top + 18
        x = 12
        x += @buttons.icon(x, row, :previous, :previous, scale: 2) + 4
        x += @buttons.icon(x, row, state.paused? ? :play : :pause, :pause, scale: 2) + 4
        x += @buttons.icon(x, row, :next, :next, scale: 2) + 8
        x += @painter.text(x, row + 6, "TUNE #{state.tune}/#{state.tunes}", SIDView::BRIGHT) + 24
        draw_subtunes(state, x, row + 4)
        draw_toggles(state, row + 4)
      end

      # The seconds into the subtune a click `left` along the bar asks for.
      def self.seek(left, length) = ((left - BAR_LEFT).to_f / BAR_WIDTH).clamp(0.0, 1.0) * length

      private

      def draw_subtunes(state, left, row)
        x = left + @painter.text(left, row + 2, "SUBTUNE", SIDView::TEXT) + 4
        x += @buttons.icon(x, row, :left, :previous_subtune)
        x += @painter.text(x + 2, row + 2, "#{state.subtune}/#{state.subtunes}", SIDView::BRIGHT) + 4
        @buttons.icon(x, row, :right, :next_subtune)
      end

      def draw_progress(state, top)
        played = state.played
        width = BAR_WIDTH
        @buttons.area([BAR_LEFT, top - 2, width, 12], :seek)
        @painter.box(BAR_LEFT, top + 2, width, 4, SIDView::BOX)
        done = state.length.positive? ? (width * played / state.length).round.clamp(0, width) : 0
        @painter.box(BAR_LEFT, top + 2, done, 4, SIDView::BRIGHT)
        @painter.text(WIDTH - 16 - Painter.width(CLOCK), top, "#{clock(played)} / #{clock(state.length)}",
                      SIDView::TEXT)
      end

      def draw_toggles(state, row)
        x = PlayerHeader.right_aligned(TOGGLES)
        TOGGLES.each_with_index do |label, toggle|
          x += @buttons.text(x, row, label, TOGGLE_ACTIONS[toggle], on: state.on?(TOGGLE_NOTES[toggle])) + 4
        end
      end

      def clock(seconds)
        whole = seconds.floor
        format("%<minutes>d:%<seconds>02d", minutes: whole / 60, seconds: whole % 60)
      end
    end
  end
end
