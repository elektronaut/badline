# frozen_string_literal: true

module Badline
  module Frontend
    # The Screen the window shows: the machine's video chip's, or on the
    # C128 the VDC's, two of its dots to a window pixel, once #show_vdc
    # switches to it. Only the chip shown renders. The VDC's display changes
    # size with its registers, and the screen follows it.
    class Screens
      attr_reader :screen

      def initialize(computer)
        @computer = computer
        @vdc_shown = false
        @vdc_shape = []
        build
      end

      def vdc_shown? = @vdc_shown

      # Shows another machine's video chip, once #build builds its screen.
      def computer=(computer)
        @computer = computer
        @vdc_shown = false
      end

      # Shows the C128's VDC, or with false its VIC-IIe, once #build builds
      # its screen. Other machines have the one screen.
      def show_vdc(shown)
        return unless @computer.family == :c128

        @vdc_shown = shown
        @computer.vdc_shown = shown
      end

      # Whether the VDC's display has changed size or crop since the screen
      # was built for it.
      def stale? = @vdc_shown && vdc_shape(@computer.vdc) != @vdc_shape

      def build
        if @vdc_shown
          vdc = @computer.vdc
          @vdc_shape = vdc_shape(vdc)
          @screen = Screen.new(vdc, vdc.crop, dots: 2)
        else
          timing = @computer.timing
          @screen = Screen.new(@computer.video, timing.crop, pixel_width: timing.pixel_width)
        end
      end

      private

      def vdc_shape(vdc) = [vdc.width, vdc.height] + vdc.crop
    end
  end
end
