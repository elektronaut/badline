# frozen_string_literal: true

module Badline
  module Frontend
    # Routes host input to the machine. Two settings decide where it goes:
    #
    # - The keys: every host key goes to the C64 keyboard, or, as Tab
    #   switches, the arrow cluster and space drive one joystick and WASD
    #   and left shift the other. The arrows start on joystick 2, and
    #   #swap_ports swaps them.
    # - A pot device the pause menu plugs into a control port: a 1351
    #   mouse or a pair of paddles, which the host mouse drives. Motion
    #   turns the paddles or moves the mouse, and the host's left and right
    #   buttons go to whichever lines the device puts them on.
    class Controls
      POTS = %i[none mouse1 mouse2 paddles1 paddles2].freeze
      TAGS = ["", "MOUSE 1", "MOUSE 2", "PADDLE 1", "PADDLE 2"].freeze

      # SDL mouse button numbers.
      MOUSE_BUTTONS = { 1 => :left, 3 => :right }.freeze

      # The pot device plugged in, one of POTS.
      attr_reader :pot, :arrows_port

      def initialize(computer)
        @computer = computer
        @joystick = false
        @pot = :none
        @arrows_port = 2
        @mouse = Input::Mouse1351.new
        @paddles = Input::Paddles.new
      end

      # Routes the input to another machine, the pot device going into its
      # port.
      def computer=(computer)
        release_all
        @computer = computer
        attach_pot_device
      end

      def joystick_mode? = @joystick

      # Sends the keys to the joysticks, or with false to the keyboard.
      def joystick_mode=(joystick)
        @joystick = joystick
        release_all
      end

      def toggle_keys
        self.joystick_mode = !@joystick
      end

      # Plugs in one of POTS, in place of the one before.
      def plug(pot)
        @pot = pot
        release_all
        attach_pot_device
      end

      # Whether the host mouse drives a pot device, and so should be held
      # in relative mode.
      def pot_device? = @pot != :none

      # The title bar's tag for the settings, empty for the keyboard alone.
      def tag
        tags = []
        tags << "JOY #{@arrows_port}" if @joystick
        tags << TAGS[POTS.index(@pot)] if pot_device?
        tags.join(", ")
      end

      def key(scancode, down)
        if joystick_mode? && Keys.joystick?(scancode)
          joystick_key(scancode, down)
        else
          c64_key(Keys.c64_key(scancode), down)
        end
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

      # RESTORE isn't in the key matrix, so it goes to the machine instead.
      def c64_key(key, down)
        if key == :restore
          @computer.press_restore if down
        else
          down ? @computer.keyboard.press(key) : @computer.keyboard.release(key)
        end
      end

      def paddles? = POTS.index(@pot) >= 3

      # A fresh pot device on its port, and none on the other.
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

      def port_one? = %i[mouse1 paddles1].include?(@pot)

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
