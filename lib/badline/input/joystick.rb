# frozen_string_literal: true

module Badline
  module Input
    class Joystick
      DIRECTIONS = { up: 0, down: 1, left: 2, right: 3, fire: 4 }.freeze

      # Kept up to date as switches move, since the CIA samples the fire line
      # every cycle to drive the light pen input.
      attr_reader :port_bits

      def initialize
        @port_bits = 0xff
        @change_handler = nil
      end

      # Register a handler called after a press or a release. On the VIC-20,
      # this passes the fire button on to the VIC's light pen input.
      def on_change(&handler)
        @change_handler = handler
      end

      def press(direction)
        bit = DIRECTIONS[direction]
        return unless bit

        @port_bits &= ~(1 << bit)
        @change_handler&.call
      end

      def release(direction)
        bit = DIRECTIONS[direction]
        return unless bit

        @port_bits |= 1 << bit
        @change_handler&.call
      end
    end
  end
end
