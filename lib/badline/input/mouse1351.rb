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
    # #move takes host pixel deltas with y counting down the screen; the counter
    # counts the other way. Two host pixels make one count, as in VICE, and the
    # counters keep the odd half count so slow movement adds up. Motion waits
    # until the pot register is read, and at most 31 counts of it reach the
    # counter per read, so a fast flick can't wrap the counter into the
    # opposite direction. The left button sits on the joystick fire line, the
    # right button on the up line.
    class Mouse1351
      BUTTONS = { left: :fire, right: :up }.freeze
      MAX_TRAVEL = 62

      def initialize
        @lines = Joystick.new
        @x = 0
        @y = 0
        @pending_x = 0
        @pending_y = 0
      end

      def press(button) = @lines.press(BUTTONS[button])

      def release(button) = @lines.release(BUTTONS[button])

      def port_bits = @lines.port_bits

      def move(delta_x, delta_y)
        @pending_x = (@pending_x + delta_x).clamp(-MAX_TRAVEL, MAX_TRAVEL)
        @pending_y = (@pending_y - delta_y).clamp(-MAX_TRAVEL, MAX_TRAVEL)
      end

      def pot_x
        @x = (@x + @pending_x) & 0x7f
        @pending_x = 0
        @x & 0x7e
      end

      def pot_y
        @y = (@y + @pending_y) & 0x7f
        @pending_y = 0
        @y & 0x7e
      end
    end
  end
end
