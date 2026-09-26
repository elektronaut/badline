# frozen_string_literal: true

module Badline
  module Native
    # Routes host input to the machine in one of badline-ruby's input modes,
    # which Tab steps through and shift-Tab steps back through:
    #
    # - keyboard: every host key goes to the C64 keyboard.
    # - joystick: the arrow cluster and space drive one joystick and WASD
    #   and left shift the other. The arrows start on joystick 2, and F9
    #   swaps them.
    # - mouse1, mouse2: the host mouse is a 1351 mouse on control port 1 or
    #   2, and paddles1, paddles2 a pair of paddles there. Motion turns the
    #   paddles or moves the mouse, and the host's left and right buttons go
    #   to whichever lines the device puts them on.
    class Controls
      MODES = %i[keyboard joystick mouse1 mouse2 paddles1 paddles2].freeze
      TAGS = ["", "JOY", "MOUSE 1", "MOUSE 2", "PADDLE 1", "PADDLE 2"].freeze

      # SDL mouse button numbers.
      MOUSE_BUTTONS = { 1 => :left, 3 => :right }.freeze

      attr_reader :mode, :arrows_port

      def initialize(computer)
        @computer = computer
        @mode = :keyboard
        @arrows_port = 2
        @mouse = Input::Mouse1351.new
        @paddles = Input::Paddles.new
      end

      def joystick_mode? = @mode == :joystick

      # Whether the host mouse drives a pot device, and so should be held
      # in relative mode.
      def pot_device? = MODES.index(@mode) >= 2

      # The title bar's tag for the mode, empty for the keyboard.
      def tag
        return "JOY #{@arrows_port}" if joystick_mode?

        TAGS[MODES.index(@mode)]
      end

      def key(scancode, down)
        if joystick_mode? && Keys.joystick?(scancode)
          joystick_key(scancode, down)
        else
          key = Keys.c64_key(scancode)
          down ? @computer.keyboard.press(key) : @computer.keyboard.release(key)
        end
      end

      # Steps to the next mode, or back with a negative step.
      def cycle_mode(step)
        @mode = MODES[(MODES.index(@mode) + step) % MODES.size]
        release_all
        attach_pot_device
      end

      def swap_ports
        @arrows_port = 3 - @arrows_port
        release_all
      end

      def mouse_motion(delta_x, delta_y)
        return unless pot_device?

        paddles? ? @paddles.move(delta_x, delta_y) : @mouse.move(delta_x, delta_y)
      end

      def mouse_button(button, down)
        name = MOUSE_BUTTONS[button]
        return unless name && pot_device?

        if paddles?
          down ? @paddles.press(name) : @paddles.release(name)
        else
          down ? @mouse.press(name) : @mouse.release(name)
        end
      end

      private

      def paddles? = MODES.index(@mode) >= 4

      # A fresh device on the mode's port, and none on the other.
      def attach_pot_device
        ports = @computer.control_ports
        ports.device1 = nil
        ports.device2 = nil
        return unless pot_device?

        if paddles?
          @paddles = Input::Paddles.new
          attach_paddles(ports)
        else
          @mouse = Input::Mouse1351.new
          attach_mouse(ports)
        end
      end

      def attach_paddles(ports)
        if port_one?
          ports.device1 = @paddles
        else
          ports.device2 = @paddles
        end
      end

      def attach_mouse(ports)
        if port_one?
          ports.device1 = @mouse
        else
          ports.device2 = @mouse
        end
      end

      def port_one? = %i[mouse1 paddles1].include?(@mode)

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
