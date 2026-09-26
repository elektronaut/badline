# frozen_string_literal: true

module Badline
  module GUI
    class Window
      DEFAULT_REFRESH_RATE = 60

      # SDL_DisplayMode: Uint32 format; int w, h, refresh_rate; then a pointer.
      DISPLAY_MODE_SIZE = 24

      attr_reader :renderer

      def initialize(title:, width:, height:, scale: 2, vsync: true)
        SDL.check(SDL::InitSubSystem.call(SDL::INIT_VIDEO | SDL::INIT_EVENTS))
        SDL::SetHint.call("SDL_RENDER_SCALE_QUALITY", "0") # nearest-neighbour

        @window = SDL.check_pointer(SDL::CreateWindow.call(
                                      title,
                                      SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED,
                                      width * scale, height * scale,
                                      SDL::WINDOW_RESIZABLE
                                    ))

        flags = SDL::RENDERER_ACCELERATED
        flags |= SDL::RENDERER_PRESENTVSYNC if vsync
        @renderer = SDL.check_pointer(SDL::CreateRenderer.call(@window, -1, flags))
        SDL.check(SDL::RenderSetLogicalSize.call(@renderer, width, height))
      end

      def title=(title)
        SDL::SetWindowTitle.call(@window, title)
      end

      def refresh_rate
        mode = "\0".b * DISPLAY_MODE_SIZE
        SDL.check(SDL::GetCurrentDisplayMode.call(0, mode))
        rate = mode.unpack1("l", offset: 12)
        rate.positive? ? rate : DEFAULT_REFRESH_RATE
      rescue SDL::Error
        DEFAULT_REFRESH_RATE
      end

      def draw(panes)
        SDL::SetRenderDrawColor.call(@renderer, 0, 0, 0, 255)
        SDL::RenderClear.call(@renderer)
        panes.each { |pane| pane.render(@renderer) }
        SDL::RenderPresent.call(@renderer)
      end

      def close
        return unless @window

        SDL::DestroyRenderer.call(@renderer)
        SDL::DestroyWindow.call(@window)
        SDL::QuitSubSystem.call(SDL::INIT_VIDEO | SDL::INIT_EVENTS)
        @window = nil
      end
    end
  end
end
