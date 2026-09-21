# frozen_string_literal: true

module Badline
  module Input
    # A pair of paddles on one control port.
    #
    # Paddle A sits on POTX with its button on the joystick left line, paddle B
    # on POTY with its button on the right line. Positions are the 0-255 counts
    # SID reads back, and the knobs stop at either end.
    class Paddles
      BUTTONS = { a: :left, b: :right }.freeze

      attr_reader :pot_x, :pot_y

      def initialize
        @lines = Joystick.new
        @pot_x = 0x80
        @pot_y = 0x80
      end

      def press(button) = @lines.press(BUTTONS[button])

      def release(button) = @lines.release(BUTTONS[button])

      def port_bits = @lines.port_bits

      def move(turn_a, turn_b)
        @pot_x = (@pot_x + turn_a).clamp(0, 0xff)
        @pot_y = (@pot_y + turn_b).clamp(0, 0xff)
      end
    end
  end
end
