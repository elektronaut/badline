# frozen_string_literal: true

module Badline
  module GUI
    # The true drive's red LED, in the bottom right corner of the border:
    # bright while the DOS lights it, as it does while a file is open or
    # after an error, and dim otherwise.
    class DriveLedPane < Pane
      WIDTH = 12
      HEIGHT = 4
      LEFT = ScreenPane::WIDTH - WIDTH - 8
      TOP = ScreenPane::HEIGHT - HEIGHT - 6

      LIT = [0xff, 0x20, 0x20].freeze
      DARK = [0x40, 0x00, 0x00].freeze

      def initialize(drive, left: LEFT, top: TOP)
        super(width: WIDTH, height: HEIGHT, left:, top:)
        @drive = drive
      end

      def color = @drive.mechanism.led_on? ? LIT : DARK

      def render(renderer)
        SDL::SetRenderDrawColor.call(renderer, *color, 0xff)
        SDL::RenderFillRect.call(renderer, @rect)
      end
    end
  end
end
