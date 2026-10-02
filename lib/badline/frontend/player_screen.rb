# frozen_string_literal: true

module Badline
  module Frontend
    # The SDL window the SID player draws in, and its drawing: the header,
    # the body of the view picked, and the footer, at the height the view
    # needs, in logical pixels scaled up twice.
    class PlayerScreen
      WIDTH = PlayerHeader::WIDTH
      HEADER = 64
      SCALE = 2
      TITLE = "Badline"
      BACKGROUND = Screen::COLORS[6]

      attr_reader :buttons, :info

      def initialize
        @window = nil
        @renderer = nil
        @painter = nil
        @buttons = nil
        @info = nil
        @sids = 1
      end

      def open?
        !@window.nil?
      end

      def open(view)
        SDL.SDL_InitSubSystem(SDL::INIT_VIDEO | SDL::INIT_EVENTS)
        SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")
        @window = SDL.SDL_CreateWindow(TITLE, SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED,
                                       WIDTH * SCALE, height(view) * SCALE, SDL::WINDOW_RESIZABLE)
        @renderer = SDL.SDL_CreateRenderer(@window, -1, SDL::RENDERER_ACCELERATED)
        SDL.SDL_RenderSetLogicalSize(@renderer, WIDTH, height(view))
        build
      end

      def close
        return unless open?

        @painter.close
        SDL.SDL_DestroyRenderer(@renderer)
        SDL.SDL_DestroyWindow(@window)
        SDL.SDL_QuitSubSystem(SDL::INIT_VIDEO | SDL::INIT_EVENTS)
        @window = nil
      end

      # Fits the window to the view's height.
      def resize(view)
        SDL.SDL_SetWindowSize(@window, WIDTH * SCALE, height(view) * SCALE)
        SDL.SDL_RenderSetLogicalSize(@renderer, WIDTH, height(view))
      end

      # Fits the window to a tune on `sids` SIDs, whose SID view is taller
      # than one on a single SID.
      def fit_sids(view, sids)
        return if sids == @sids

        @sids = sids
        resize(view) if open?
      end

      # Names the tune in the window's title.
      def title(name)
        SDL.SDL_SetWindowTitle(@window, name.empty? ? TITLE : "#{name} - #{TITLE}") if open?
      end

      # Draws a frame of the player: `player` and `history` are the SIDs',
      # nil before anything plays, and `credit` the header's STIL credit.
      def draw(state, player, history, tune, credit)
        return unless open?

        SDL.SDL_SetRenderDrawColor(@renderer, (BACKGROUND >> 16) & 0xff, (BACKGROUND >> 8) & 0xff,
                                   BACKGROUND & 0xff, 255)
        SDL.SDL_RenderClear(@renderer)
        @buttons.forget
        @top.draw(state, tune, player.nil? ? [] : player.stereo.models, credit)
        player.nil? ? draw_empty(state.view) : draw_body(state, player, history)
        @bottom.draw(state, height(state.view) - PlayerFooter::HEIGHT)
        SDL.SDL_RenderPresent(@renderer)
      end

      private

      def height(view) = HEADER + body_height(view) + PlayerFooter::HEIGHT

      def body_height(view) = view == 1 ? SIDView.height(@sids) : VisualizerView::HEIGHT

      def build
        @painter = Painter.new(@renderer)
        @buttons = Buttons.new(@painter)
        @top = PlayerHeader.new(@painter, @buttons)
        @bottom = PlayerFooter.new(@painter, @buttons)
        @visualizer = VisualizerView.new(@painter, HEADER + 4)
        @sid_view = SIDView.new(@painter, @buttons, HEADER + 4)
        @info = InfoView.new(@painter, @buttons, HEADER + 4)
      end

      def draw_body(state, player, history)
        played = state.played
        case state.view
        when 0 then @visualizer.draw(history, played, clock_hz: player.clock_hz)
        when 1 then draw_sid(state.sid, player, history, played)
        else @info.draw
        end
      end

      # The SID view of the SID picked, or of the last a tune has.
      def draw_sid(sid, player, history, played)
        models = player.stereo.models
        shown = [sid, models.size - 1].min
        @sid_view.draw(history, played, clock_hz: player.clock_hz, model: models[shown], sid: shown)
      end

      def draw_empty(view)
        hint = "Drop .sid files or folders here"
        @painter.text((WIDTH - Painter.width(hint, scale: 2)) / 2, HEADER + (body_height(view) / 2) - 8, hint,
                      SIDView::TEXT, scale: 2)
      end
    end
  end
end
