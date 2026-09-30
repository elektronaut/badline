# frozen_string_literal: true

module Badline
  module GUI
    # The true drive's red LED, in the bottom right corner of the screen
    # pane's border: bright while the DOS lights it, as it does while a file
    # is open or after an error, and dim otherwise.
    class DriveLedPane < Pane
      WIDTH = 12
      HEIGHT = 4

      LIT = [0xff, 0x20, 0x20].freeze
      DARK = [0x40, 0x00, 0x00].freeze

      def initialize(drive, screen)
        super(width: WIDTH, height: HEIGHT,
              left: screen.left + screen.width - WIDTH - 8, top: screen.top + screen.height - HEIGHT - 6)
        @drive = drive
      end

      def color = @drive.led_on? ? LIT : DARK

      def render(renderer)
        SDL.SDL_SetRenderDrawColor(renderer, *color, 0xff)
        SDL.SDL_RenderFillRect(renderer, @rect)
      end
    end
  end
end
