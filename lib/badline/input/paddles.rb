# frozen_string_literal: true

module Badline
  module Input
    # A pair of paddles on one control port.
    #
    # Paddle A sits on POTX with its button on the joystick left line, paddle B
    # on POTY with its button on the right line. Positions are the 0-255 counts
    # SID reads back, and the knobs stop at either end.
    #
    # #move takes host pixel deltas, two to a count, and the knobs keep the odd
    # half count so slow turns add up.
    #
    # Buttons are named after the host mouse buttons, as on the 1351: the left
    # one fires paddle A, the right one paddle B.
    class Paddles
      BUTTONS = { left: :left, right: :right }.freeze

      def initialize
        @lines = Joystick.new
        @half_x = 0x100
        @half_y = 0x100
      end

      def press(button) = @lines.press(BUTTONS[button])

      def release(button) = @lines.release(BUTTONS[button])

      def port_bits = @lines.port_bits

      def move(turn_a, turn_b)
        @half_x = (@half_x + turn_a).clamp(0, 0x1ff)
        @half_y = (@half_y + turn_b).clamp(0, 0x1ff)
      end

      def pot_x = @half_x >> 1

      def pot_y = @half_y >> 1
    end
  end
end
