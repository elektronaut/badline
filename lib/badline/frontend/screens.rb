# frozen_string_literal: true

module Badline
  module Frontend
    # The Screen the window shows: the machine's video chip's, or on the
    # C128 the VDC's, two of its dots to a window pixel, once #show_vdc
    # switches to it. Only the chip shown renders. The VDC's display changes
    # size with its registers, and the screen follows it.
    #
    # On the C128, #follow switches to the screen the machine prints to
    # (C128#active_screen) each time it moves there, and #show_vdc's choice
    # holds until the next move.
    class Screens
      # The frames a move holds before #follow takes it. The C128 KERNAL's
      # reset clears the 80 column screen with the editor on it for over a
      # frame.
      FOLLOW_FRAMES = 3

      attr_reader :screen

      def initialize(computer)
        @computer = computer
        @vdc_shown = false
        @vdc_shape = []
        forget_screen
        build
      end

      def vdc_shown? = @vdc_shown

      # Shows another machine's video chip, once #build builds its screen.
      def computer=(computer)
        @computer = computer
        @vdc_shown = false
        forget_screen
      end

      # Shows the screen a C128 has moved its output to once the move has
      # held for FOLLOW_FRAMES calls, one a frame. #build then builds it.
      def follow
        return unless @computer.family == :c128

        vdc = @computer.active_screen == :vdc
        @held = vdc == @seen ? @held + 1 : 1
        @seen = vdc
        return if @held < FOLLOW_FRAMES || vdc == @followed

        @followed = vdc
        show_vdc(vdc)
      end

      # Shows the C128's VDC, or with false its VIC-IIe, once #build builds
      # its screen. Other machines have the one screen.
      def show_vdc(shown)
        return unless @computer.family == :c128

        @vdc_shown = shown
        @computer.vdc_shown = shown
      end

      # Whether the screen was built for the other chip, or the VDC's
      # display has changed size or crop since the screen was built for it.
      def stale? = @built_vdc != @vdc_shown || (@vdc_shown && vdc_shape(@computer.vdc) != @vdc_shape)

      def build
        @built_vdc = @vdc_shown
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

      # The machine's output counts as on the VIC-IIe's screen, the one
      # shown.
      def forget_screen
        @followed = false
        @seen = false
        @held = 0
      end

      def vdc_shape(vdc) = [vdc.width, vdc.height] + vdc.crop
    end
  end
end
