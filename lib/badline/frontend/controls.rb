# frozen_string_literal: true

module Badline
  module Frontend
    # Routes host input to the machine. Two settings decide where it goes:
    #
    # - The keys: every host key goes to the machine's keyboard, or, as Tab
    #   switches, the arrow cluster and space drive one joystick and WASD
    #   and left shift the other. The arrows start on joystick 2, and
    #   #swap_ports swaps them. The VIC-20's one joystick takes both. The
    #   PET's and the CBM-II's keys go by the character they type
    #   (PETKeyboard), and the PET and the CBM-II's B series have no
    #   joystick.
    # - A pot device the pause menu plugs into a C64 control port: a 1351
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

      # Whether the machine has joysticks: all but the PET and the CBM-II's
      # B series.
      def self.joysticks?(computer)
        family = computer.family
        family != :pet && (family != :cbm2 || p500?(computer))
      end

      # Whether the machine is the CBM-II's P500, which has the B series'
      # keyboard and two joysticks.
      def self.p500?(computer) = computer.is_a?(CBM2::P500)

      # Whether the machine's keys go by the character they type: the PET's
      # and the CBM-II's.
      def self.symbolic?(computer) = %i[pet cbm2].include?(computer.family)

      def initialize(computer)
        @computer = computer
        @joystick = false
        @pot = :none
        @arrows_port = 2
        @mouse = Input::Mouse1351.new
        @paddles = Input::Paddles.new
        @held = {}
        @pet_keyboard = pet_keyboard(computer)
      end

      # Routes the input to another machine, the pot device going into its
      # port.
      def computer=(computer)
        release_all
        @computer = computer
        @pet_keyboard = pet_keyboard(computer)
        attach_pot_device
      end

      def joystick_mode? = @joystick

      # Sends the keys to the joysticks, or with false to the keyboard.
      def joystick_mode=(joystick)
        @joystick = joystick
        release_all
      end

      # Switches between the keyboard and the joysticks, on a machine with
      # joysticks.
      def toggle_keys
        self.joystick_mode = !@joystick if tab_toggles?
      end

      # Whether Tab switches the keys to the joysticks, or on a machine
      # without them is a key of its own.
      def tab_toggles? = Controls.joysticks?(@computer)

      # Whether the machine takes a key the window would otherwise keep for
      # itself: on the CBM-II, F8, RUN/STOP on F12, Alt with F9 or F10, and
      # the release of any key it pressed.
      def claims?(scancode)
        return false unless @computer.family == :cbm2
        return true if @pet_keyboard.holds?(scancode) || [Keys::F8, Keys::F12].include?(scancode)

        @pet_keyboard.alt? && [Keys::F9, Keys::F10].include?(scancode)
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
        tags << (@computer.family == :vic20 ? "JOY" : "JOY #{@arrows_port}") if @joystick
        tags << TAGS[POTS.index(@pot)] if pot_device?
        tags.join(", ")
      end

      def key(scancode, down)
        if joystick_mode? && Keys.joystick?(scancode)
          joystick_key(scancode, down)
        else
          machine_key(scancode, down)
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

      # A host key lets go of the key it pressed, though the C128 has
      # switched between C64 and C128 mode since and maps it elsewhere.
      def machine_key(scancode, down)
        return @pet_keyboard.key(scancode, down) if Controls.symbolic?(@computer)

        @held[scancode] = host_key(scancode) if down || !@held.key?(scancode)
        key = @held[scancode]
        @held.delete(scancode) unless down
        if @computer.family == :c128
          c128_key(key, down)
        else
          c64_key(key, down)
        end
      end

      def host_key(scancode)
        case @computer.family
        when :c128 then Keys.c128_key(scancode, @computer.mode)
        when :plus4 then Keys.plus4_key(scancode)
        else Keys.c64_key(scancode)
        end
      end

      # RESTORE isn't in the key matrix, so it goes to the machine instead.
      def c64_key(key, down)
        if key == :restore
          down ? @computer.press_restore : @computer.release_restore
        else
          down ? @computer.keyboard.press(key) : @computer.keyboard.release(key)
        end
      end

      # CAPS LOCK and 40/80 DISPLAY aren't in the C128's matrix either.
      def c128_key(key, down)
        case key
        when :caps_lock then down ? @computer.press_caps_lock : @computer.release_caps_lock
        when :forty_eighty then down ? @computer.press_display_key : @computer.release_display_key
        else c64_key(key, down)
        end
      end

      def paddles? = POTS.index(@pot) >= 3

      # A fresh pot device on its port, and none on the other. A machine
      # without the ports takes none, and the P500 none yet.
      def attach_pot_device
        ports = Controls.symbolic?(@computer) ? nil : @computer.control_ports
        if ports.nil?
          @pot = :none
          return
        end

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

      # The PET's keyboard for a PET or a CBM-II, and for any other machine
      # one it never uses.
      def pet_keyboard(computer)
        layout = case computer.family
                 when :pet then computer.model.keyboard
                 when :cbm2 then :cbm2
                 else :graphics
                 end
        PETKeyboard.new(computer.keyboard, layout)
      end

      def release_all
        if Controls.symbolic?(@computer)
          @pet_keyboard.release_all
        else
          Keys::ARROWS.each_key { |scancode| @computer.keyboard.release(host_key(scancode)) }
          Keys::WASD.each_key { |scancode| @computer.keyboard.release(host_key(scancode)) }
        end
        return unless Controls.joysticks?(@computer)

        Keys::ARROWS.each_value do |direction|
          @computer.joystick1.release(direction)
          @computer.joystick2.release(direction)
        end
      end
    end
  end
end
