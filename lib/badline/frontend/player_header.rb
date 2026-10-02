# frozen_string_literal: true

module Badline
  module Frontend
    # The top of the SID player's window: the tune's name, author and
    # release, the STIL credit for what the subtune covers at the moment, a
    # warning when there is one, and the buttons for the views and the SID
    # model.
    class PlayerHeader
      WIDTH = 640
      VIEW_NAMES = %w[VISUALIZER SID INFO].freeze
      VIEWS = %i[visualizer sid info].freeze
      CHIP_NAMES = %w[AUTO 6581 8580].freeze
      CHIPS = %i[auto mos6581 mos8580].freeze

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
      end

      # Underlines the model playing while AUTO picks it.
      def draw(state, tune, playing_model, credit)
        unless tune.nil?
          @painter.text(16, 8, fit(tune.name, 26), SIDView::BRIGHT, scale: 2)
          @painter.text(16, 28, fit([tune.author, tune.released].reject(&:empty?).join(" - "), 50), SIDView::TEXT)
          @painter.text(16, 40, fit(credit, 76), SIDView::BRIGHT)
          @painter.text(16, 52, warning(state, tune), PlayerWindow::WARNING)
        end
        draw_views(state)
        draw_chips(state, playing_model)
      end

      def self.right_aligned(labels) = WIDTH - 12 - labels.sum { |label| Painter.width(label) + 8 }

      private

      def warning(state, tune)
        return tune.sids_notice unless tune.sids_notice.empty?

        state.on?("below real time") ? "Running below real time" : ""
      end

      def draw_views(state)
        x = PlayerHeader.right_aligned(VIEW_NAMES)
        VIEW_NAMES.each_with_index do |name, view|
          x += @buttons.text(x, 6, name, VIEWS[view], on: view == state.view) + 4
        end
      end

      def draw_chips(state, playing_model)
        x = PlayerHeader.right_aligned(CHIP_NAMES)
        CHIP_NAMES.each_with_index do |name, chip|
          width = @buttons.text(x, 24, name, CHIPS[chip], on: chip == state.chip)
          @painter.box(x + 2, 37, width - 4, 1, SIDView::BRIGHT) if state.chip.zero? && CHIPS[chip] == playing_model
          x += width + 4
        end
      end

      def fit(text, chars) = text.length > chars ? "#{text[0, chars - 2]}.." : text
    end
  end
end
