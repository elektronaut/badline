# frozen_string_literal: true

module Badline
  module Frontend
    # One game controller's state wired onto a joystick: the D-pad and the
    # left stick both steer, and every face and shoulder button fires. It
    # only releases directions it pressed itself, so the keyboard's joystick
    # keys keep working with a controller connected.
    class PadPort
      DEADZONE = 8_000

      # SDL_GameControllerButton values.
      BUTTON_COUNT = 15
      BUTTONS = {
        up: [11], down: [12], left: [13], right: [14],
        fire: [0, 1, 2, 3, 9, 10] # A, B, X, Y and the shoulders
      }.freeze

      # SDL_GameControllerAxis values, and the sign that steers each way.
      LEFT_X = 0
      LEFT_Y = 1
      AXES = { up: [LEFT_Y, -1], down: [LEFT_Y, 1], left: [LEFT_X, -1], right: [LEFT_X, 1] }.freeze

      DIRECTIONS = %i[up down left right fire].freeze

      attr_reader :pressed

      def initialize(joystick)
        @joystick = joystick
        @pressed = []
      end

      # The directions a controller holds, from its `buttons` (0 or 1 for
      # each SDL button) and its left stick.
      def self.active(buttons, left_x, left_y)
        DIRECTIONS.select do |direction|
          BUTTONS[direction].any? { |button| buttons[button] != 0 } ||
            tilted?(direction, left_x, left_y)
        end
      end

      def self.tilted?(direction, left_x, left_y)
        return false if direction == :fire

        axis, sign = AXES[direction]
        (axis == LEFT_X ? left_x : left_y) * sign > DEADZONE
      end

      # Presses what the controller holds and releases what it let go of.
      def update(active)
        @pressed.each { |direction| @joystick.release(direction) unless active.include?(direction) }
        active.each { |direction| @joystick.press(direction) }
        @pressed = active
      end

      def release
        update([])
      end
    end
  end
end
