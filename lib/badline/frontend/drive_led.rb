# frozen_string_literal: true

module Badline
  module Frontend
    # The true drive's LEDs, drawn over the bottom right corner of the
    # border: the red activity LED, bright while the DOS lights it, as it
    # does while a file is open or after an error, and dim otherwise, and
    # left of it the green power LED, which a 1581 flashes after an error.
    # They follow whichever true drive the machine has, one plugged in
    # after start among them, and are drawn only while it has one.
    class DriveLed
      WIDTH = 12
      HEIGHT = 4

      # The power LED's distance left of the activity LED.
      POWER_OFFSET = WIDTH + 4

      LIT = [0xff, 0x20, 0x20].freeze
      DARK = [0x40, 0x00, 0x00].freeze
      POWER_LIT = [0x20, 0xff, 0x20].freeze
      POWER_DARK = [0x00, 0x40, 0x00].freeze

      # Sets SDL.led_rect to where the activity LED goes on a screen `width`
      # by `height`, or with `offset` that many pixels left of it.
      def self.place(width, height, offset = 0)
        rect = SDL.led_rect
        SDL.rect_x(rect, width - WIDTH - 8 - offset)
        SDL.rect_y(rect, height - HEIGHT - 6)
        SDL.rect_w(rect, WIDTH)
        SDL.rect_h(rect, HEIGHT)
      end

      def initialize(computer)
        @computer = computer
      end

      # Whether the machine has a true drive, and so LEDs to draw.
      def shown? = !@computer.true_drive.nil?

      def lit?
        drive = @computer.true_drive
        drive.nil? ? false : drive.led_on?
      end

      def power_lit?
        drive = @computer.true_drive
        drive.nil? ? false : drive.power_led_on?
      end

      def color = lit? ? LIT : DARK

      def power_color = power_lit? ? POWER_LIT : POWER_DARK

      # Fills the LEDs' rectangles on a screen `width` by `height` in their
      # colours, then puts back the black that RenderClear clears with.
      def draw(renderer, width, height)
        return unless shown?

        fill(renderer, width, height, 0, color)
        fill(renderer, width, height, POWER_OFFSET, power_color)
        SDL.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
      end

      private

      def fill(renderer, width, height, offset, rgb)
        DriveLed.place(width, height, offset)
        SDL.SDL_SetRenderDrawColor(renderer, rgb[0], rgb[1], rgb[2], 255)
        SDL.SDL_RenderFillRect(renderer, SDL.led_rect)
      end
    end
  end
end
