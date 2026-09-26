# frozen_string_literal: true

module Badline
  module Native
    # Routes host keys to the C64 keyboard or, in joystick mode, the arrow
    # cluster and WASD to the two joysticks. The arrows start on joystick 2.
    class Controls
      attr_reader :joystick_mode, :arrows_port

      def initialize(computer)
        @computer = computer
        @joystick_mode = false
        @arrows_port = 2
      end

      def key(scancode, down)
        if @joystick_mode && Keys.joystick?(scancode)
          joystick_key(scancode, down)
        else
          key = Keys.c64_key(scancode)
          down ? @computer.keyboard.press(key) : @computer.keyboard.release(key)
        end
      end

      def toggle_joystick_mode
        @joystick_mode = !@joystick_mode
        release_all
      end

      def swap_ports
        @arrows_port = 3 - @arrows_port
        release_all
      end

      private

      def joystick_key(scancode, down)
        direction = Keys.arrows(scancode)
        if direction == :none
          move(joystick(3 - @arrows_port), Keys.wasd(scancode), down)
        else
          move(joystick(@arrows_port), direction, down)
        end
      end

      def joystick(port) = port == 1 ? @computer.joystick1 : @computer.joystick2

      def move(joystick, direction, down)
        down ? joystick.press(direction) : joystick.release(direction)
      end

      def release_all
        Keys::ARROWS.each_key { |scancode| @computer.keyboard.release(Keys.c64_key(scancode)) }
        Keys::WASD.each_key { |scancode| @computer.keyboard.release(Keys.c64_key(scancode)) }
        Keys::ARROWS.each_value do |direction|
          @computer.joystick1.release(direction)
          @computer.joystick2.release(direction)
        end
      end
    end
  end
end
