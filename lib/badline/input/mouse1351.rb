# frozen_string_literal: true

module Badline
  module Input
    # Commodore 1351 mouse in proportional mode.
    #
    # Each axis drives a 6-bit counter that the mouse presents on POTX/POTY
    # shifted up one bit. A driver recovers movement by masking off bit 7,
    # subtracting the previous reading and halving the difference. The counters
    # wrap, so a single reading says nothing on its own, and the driver has to
    # sample before the mouse travels 32 counts.
    #
    # #move takes host deltas with y counting down the screen; the counter
    # counts the other way. The left button sits on the joystick fire line, the
    # right button on the up line.
    class Mouse1351
      BUTTONS = { left: :fire, right: :up }.freeze

      def initialize
        @lines = Joystick.new
        @x = 0
        @y = 0
      end

      def press(button) = @lines.press(BUTTONS[button])

      def release(button) = @lines.release(BUTTONS[button])

      def port_bits = @lines.port_bits

      def move(delta_x, delta_y)
        @x = (@x + delta_x) & 0x3f
        @y = (@y - delta_y) & 0x3f
      end

      def pot_x = @x << 1

      def pot_y = @y << 1
    end
  end
end
