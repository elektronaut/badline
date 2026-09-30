# frozen_string_literal: true

module Badline
  module GUI
    class Window
      DEFAULT_REFRESH_RATE = 60

      attr_reader :renderer

      def initialize(title:, width:, height:, scale: 2, vsync: true)
        SDLError.check(SDL.SDL_InitSubSystem(SDL::INIT_VIDEO | SDL::INIT_EVENTS))
        SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0") # nearest-neighbour
        SDL.SDL_SetHint("SDL_MOUSE_RELATIVE_SCALING", "0") # host pixels, whatever the window size

        @window = SDLError.check_pointer(SDL.SDL_CreateWindow(
                                           title,
                                           SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED,
                                           width * scale, height * scale,
                                           SDL::WINDOW_RESIZABLE
                                         ))

        flags = SDL::RENDERER_ACCELERATED
        flags |= SDL::RENDERER_PRESENTVSYNC if vsync
        @renderer = SDLError.check_pointer(SDL.SDL_CreateRenderer(@window, -1, flags))
        SDLError.check(SDL.SDL_RenderSetLogicalSize(@renderer, width, height))
      end

      def title=(title)
        SDL.SDL_SetWindowTitle(@window, title)
      end

      def refresh_rate
        return DEFAULT_REFRESH_RATE if SDL.SDL_GetCurrentDisplayMode(0, SDL.display_mode).negative?

        rate = SDL.mode_refresh(SDL.display_mode)
        rate.positive? ? rate : DEFAULT_REFRESH_RATE
      end

      def draw(panes)
        SDL.SDL_SetRenderDrawColor(@renderer, 0, 0, 0, 255)
        SDL.SDL_RenderClear(@renderer)
        panes.each { |pane| pane.render(@renderer) }
        SDL.SDL_RenderPresent(@renderer)
      end

      def close
        return unless @window

        SDL.SDL_DestroyRenderer(@renderer)
        SDL.SDL_DestroyWindow(@window)
        SDL.SDL_QuitSubSystem(SDL::INIT_VIDEO | SDL::INIT_EVENTS)
        @window = nil
      end
    end
  end
end
