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
    #   joystick. The KIM-1's host keys press its panel's (Keys::KIM1_KEYS),
    #   and so does a click on one the window draws.
    # - A pot device the pause menu plugs into a control port of a C64, a
    #   C128 or a P500: a 1351 mouse or a pair of paddles, which the host
    #   mouse drives. Motion
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
        family != :pet && family != :kim1 && (family != :cbm2 || p500?(computer))
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
        @clicked = ""
        @shifts = 0
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

      # Presses the KIM-1 key KIM1Panel names `name` for a click on it, or
      # lets go of the key the last click pressed.
      def panel_click(name, down)
        if down
          @clicked = name
          kim1_key(name, true) unless name.empty?
        else
          kim1_key(@clicked, false) unless @clicked.empty?
          @clicked = ""
        end
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
        if Controls.symbolic?(@computer)
          @pet_keyboard.positional = @computer.family == :pet && @computer.apl_characters? if down
          return @pet_keyboard.key(scancode, down)
        end
        return kim1_input(scancode, down) if @computer.family == :kim1

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

      # The keys type on the teletype with the KIM-1's jumper fitted, and
      # press the panel's keys without it.
      def kim1_input(scancode, down)
        return kim1_key(Keys.kim1_key(scancode), down) unless @computer.tty?
        return shift(down) if [225, 229].include?(scancode)

        text = Keys.kim1_teletype(scancode, @shifts.positive?)
        @computer.teletype.type(text) if down && !text.empty?
      end

      def shift(down)
        @shifts += down ? 1 : -1
        @shifts = 0 if @shifts.negative?
      end

      # ST pulls NMI and RS resets as they go down, and T flips the SST
      # switch. The other keys stay down until let go.
      def kim1_key(name, down)
        case name
        when "" then nil
        when "ST" then @computer.press_stop if down
        when "RS" then @computer.press_reset if down
        when "SST" then @computer.sst = !@computer.sst if down
        else
          if down
            @computer.press_key(name)
          elsif @computer.panel.held == name
            @computer.release_key
          end
        end
      end

      def paddles? = POTS.index(@pot) >= 3

      # A fresh pot device on its port, and none on the other. A machine
      # without the ports takes none.
      def attach_pot_device
        portless = Controls.symbolic?(@computer) || @computer.family == :kim1
        ports = Controls.p500?(@computer) || !portless ? @computer.control_ports : nil
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
      # one it never uses, on a keyboard of its own for the KIM-1, which has
      # none.
      def pet_keyboard(computer)
        layout = case computer.family
                 when :pet then computer.model.keyboard
                 when :cbm2 then :cbm2
                 else :graphics
                 end
        keyboard = computer.family == :kim1 ? Input::Keyboard.new : computer.keyboard
        PETKeyboard.new(keyboard, layout)
      end

      def release_all
        return @computer.release_key if @computer.family == :kim1

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
