# frozen_string_literal: true

module Badline
  class CBM2
    # The CRTC's output while nothing paints the picture: it hears each
    # character, sync and frame and draws nothing.
    class BlankVideo
      def character(_address, _line, _since_hsync); end

      def hsync; end

      def line_end; end

      def rows_end; end

      def frame_start; end
    end
  end
end
