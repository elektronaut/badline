# frozen_string_literal: true

module Badline
  module Frontend
    # The top of the SID player's window: the tune's name, author and
    # release, the STIL credit for what the subtune covers at the moment, a
    # warning when there is one, and the buttons for the views and the SID
    # model. The SID view of a tune on more than one SID gets a button for
    # each SID beside the views', which picks the SID it shows.
    class PlayerHeader
      WIDTH = 640
      VIEW_NAMES = %w[VISUALIZER SID INFO].freeze
      VIEWS = %i[visualizer sid info].freeze
      CHIP_NAMES = %w[AUTO 6581 8580].freeze
      CHIPS = %i[auto mos6581 mos8580].freeze
      SID_NAMES = ["SID 1", "SID 2", "SID 3"].freeze
      SIDS = %i[sid1 sid2 sid3].freeze

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
      end

      # Underlines the models playing while AUTO picks them.
      def draw(state, tune, playing_models, credit)
        sids = tune.nil? || state.view != 1 ? 1 : tune.sids
        unless tune.nil?
          @painter.text(16, 8, fit(tune.name, sids > 1 ? 18 : 26), SIDView::BRIGHT, scale: 2)
          @painter.text(16, 28, fit([tune.author, tune.released].reject(&:empty?).join(" - "), 50), SIDView::TEXT)
          @painter.text(16, 40, fit(credit, 76), SIDView::BRIGHT)
          @painter.text(16, 52, warning(state), PlayerWindow::WARNING)
        end
        draw_views(state)
        draw_sids(state, sids) if sids > 1
        draw_chips(state, playing_models)
      end

      def self.right_aligned(labels) = WIDTH - 12 - labels.sum { |label| Painter.width(label) + 8 }

      private

      def warning(state) = state.on?("below real time") ? "Running below real time" : ""

      def draw_views(state)
        x = PlayerHeader.right_aligned(VIEW_NAMES)
        VIEW_NAMES.each_with_index do |name, view|
          x += @buttons.text(x, 6, name, VIEWS[view], on: view == state.view) + 4
        end
      end

      # Left of the views' buttons, the SID shown on.
      def draw_sids(state, sids)
        names = SID_NAMES.first(sids)
        x = PlayerHeader.right_aligned(VIEW_NAMES) - 8 - names.sum { |name| Painter.width(name) + 8 }
        names.each_with_index do |name, sid|
          x += @buttons.text(x, 6, name, SIDS[sid], on: sid == [state.sid, sids - 1].min) + 4
        end
      end

      def draw_chips(state, playing_models)
        x = PlayerHeader.right_aligned(CHIP_NAMES)
        CHIP_NAMES.each_with_index do |name, chip|
          width = @buttons.text(x, 24, name, CHIPS[chip], on: chip == state.chip)
          if state.chip.zero? && playing_models.include?(CHIPS[chip])
            @painter.box(x + 2, 37, width - 4, 1, SIDView::BRIGHT)
          end
          x += width + 4
        end
      end

      def fit(text, chars) = text.length > chars ? "#{text[0, chars - 2]}.." : text
    end
  end
end
