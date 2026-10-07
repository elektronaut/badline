# frozen_string_literal: true

module Badline
  module Frontend
    # The emulator's SDL window, its renderer and the streaming texture a
    # Screen's pixels go into. The renderer's logical size is the screen's,
    # with each of its pixels `pixel_width` square pixels wide, so the
    # picture keeps the machine's aspect while the menu and the drive LED
    # draw in square pixels over it. The window opens at SCALE times that.
    class MachineWindow
      SCALE = 2
      TITLE = "Badline"

      # The logical size, in square pixels.
      attr_reader :width, :height

      attr_reader :renderer, :texture

      # Opens the window for `screen`, presenting in step with the display
      # when `vsync`.
      def initialize(screen, pixel_width, vsync:)
        abort "SDL_Init: #{SDL.SDL_GetError}" unless SDL.SDL_Init(SDL::INIT_VIDEO | SDL::INIT_EVENTS).zero?

        SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")
        SDL.SDL_SetHint("SDL_MOUSE_RELATIVE_SCALING", "0")
        measure(screen, pixel_width)
        @window = SDL.SDL_CreateWindow(
          TITLE, SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED, @width * SCALE, @height * SCALE,
          SDL::WINDOW_RESIZABLE
        )
        flags = SDL::RENDERER_ACCELERATED
        flags |= SDL::RENDERER_PRESENTVSYNC if vsync
        @renderer = SDL.SDL_CreateRenderer(@window, -1, flags)
        create_texture
      end

      # The refresh rate of the display the window is on, in Hz.
      def refresh_rate
        SDL.SDL_GetWindowDisplayMode(@window, SDL.display_mode)
        SDL.mode_refresh(SDL.display_mode)
      end

      # Fits the texture, the logical size and the window to another
      # machine's screen, unless it measures the same.
      def fit(screen, pixel_width)
        before = [@width, @height, @texture_width]
        measure(screen, pixel_width)
        return if before == [@width, @height, @texture_width]

        SDL.SDL_DestroyTexture(@texture)
        create_texture
        SDL.SDL_SetWindowSize(@window, @width * SCALE, @height * SCALE)
      end

      def upload(screen)
        SDL.SDL_UpdateTexture(@texture, nil, screen.pixels, screen.row_bytes)
      end

      # Titles the window, TITLE followed by `tags` in brackets.
      def title(tags)
        SDL.SDL_SetWindowTitle(@window, ([TITLE] + tags.map { |tag| "[#{tag}]" }).join(" "))
      end

      def close
        SDL.SDL_DestroyTexture(@texture)
        SDL.SDL_DestroyRenderer(@renderer)
        SDL.SDL_DestroyWindow(@window)
        SDL.SDL_Quit
      end

      private

      def measure(screen, pixel_width)
        @texture_width = screen.width
        @width = screen.width * pixel_width
        @height = screen.height
      end

      def create_texture
        SDL.SDL_RenderSetLogicalSize(@renderer, @width, @height)
        @texture = SDL.SDL_CreateTexture(
          @renderer, SDL::PIXELFORMAT_RGB888, SDL::TEXTUREACCESS_STREAMING, @texture_width, @height
        )
      end
    end
  end
end
