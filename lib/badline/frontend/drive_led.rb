# frozen_string_literal: true

module Badline
  module Frontend
    # The true drive's red LED, drawn over the bottom right corner of the
    # border: bright while the DOS lights it, as it does while a file is
    # open or after an error, and dim otherwise.
    class DriveLed
      WIDTH = 12
      HEIGHT = 4

      LIT = [0xff, 0x20, 0x20].freeze
      DARK = [0x40, 0x00, 0x00].freeze

      # The LED of the machine's true drive, or nil without one.
      def self.for(computer)
        drive = computer.drive1541
        drive ? new(drive) : nil
      end

      # Sets SDL.led_rect to where the LED goes on a screen `width` by
      # `height`.
      def self.place(width, height)
        rect = SDL.led_rect
        SDL.rect_x(rect, width - WIDTH - 8)
        SDL.rect_y(rect, height - HEIGHT - 6)
        SDL.rect_w(rect, WIDTH)
        SDL.rect_h(rect, HEIGHT)
      end

      def initialize(drive)
        @drive = drive
      end

      def lit? = @drive.led_on?

      def color = lit? ? LIT : DARK

      # Fills the LED's rectangle on a screen `width` by `height` in its
      # colour, then puts back the black that RenderClear clears with.
      def draw(renderer, width, height)
        DriveLed.place(width, height)
        rgb = color
        SDL.SDL_SetRenderDrawColor(renderer, rgb[0], rgb[1], rgb[2], 255)
        SDL.SDL_RenderFillRect(renderer, SDL.led_rect)
        SDL.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
      end
    end
  end
end
