# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's PORTS page, which MenuPages draws: what each C64
    # control port has plugged in, a joystick or a pot device, and whether
    # the keys type or drive the joysticks. The VIC-20 has one port, a
    # joystick's, and the Plus/4 two joysticks and no pot devices. The PET
    # and the CBM-II's B series have no ports, and the page, KEYBOARD
    # there, says where their keys are instead. The P500 has two joysticks,
    # and the page says where its keys are while they type. The KIM-1's,
    # PANEL there, sets its SST switch and TTY/KB jumper, which presses RS
    # for the monitor to start again on the keypad or the teletype, and what its
    # application connector wires: U3's PB7 to IRQ, and a speaker on U3's
    # PA0 in place of the audio output on U2's PB7.
    module MenuPorts
      PORT_DEVICES = %i[joystick mouse paddles].freeze
      PORT_NAMES = %w[JOY MOUSE PADDLES].freeze
      PORT_ACTIONS = [%i[port1_joystick port1_mouse port1_paddles], %i[port2_joystick port2_mouse port2_paddles]].freeze
      POTS = [%i[none mouse1 paddles1], %i[none mouse2 paddles2]].freeze

      # Where the PET's keys without a character of their own are, on both
      # keyboards, and then on the graphics one and on the business one.
      PET_KEYS = ["PAGE DOWN: RUN/STOP", "HOME: CLR/HOME", "BACKSPACE: INST/DEL", "CTRL: RVS",
                  "ARROWS: CURSOR", "^: UP ARROW", "_: LEFT ARROW"].freeze
      PET_GRAPHICS_KEYS = ["ESC: RUN/STOP", "SHIFT+LETTER: GRAPHIC", "ALT+SYMBOL: GRAPHIC"].freeze
      PET_BUSINESS_KEYS = ["ESC: ESC", "TAB: TAB", "PAGE UP: REPEAT", "KEYPAD: KEYPAD", "ALT+KEY: SHIFT+KEY"].freeze

      # Where the CBM-II's keys without a character of their own are.
      CBM2_KEYS = ["ESC: ESC", "F12: RUN/STOP", "HOME: CLR/HOME", "BACKSPACE: INST/DEL", "F1-F8: F1-F8",
                   "ALT+F9, ALT+F10: F9, F10", "KEYPAD: KEYPAD", "ALT+0: KEYPAD 00", "ALT+C: C=  ALT+E: CE",
                   "ALT+G: NORM/GRAPH", "ALT+R: OFF/RVS  ALT+P: PI", "_: LEFT ARROW"].freeze

      private

      def draw_ports
        return draw_vic20_port if @computer.family == :vic20
        return draw_plus4_ports if @computer.family == :plus4
        return draw_pet_keys if @computer.family == :pet
        return draw_p500_ports if Controls.p500?(@computer)
        return draw_cbm2_keys if @computer.family == :cbm2
        return draw_kim1_panel if @computer.family == :kim1

        draw_pot_ports
        return unless draw_keys(@computer.family == :c128 ? "C128" : "C64")

        row("SWAP JOYSTICKS", :swap)
        skip
        arrows = @controls.arrows_port
        info("ARROWS, SPACE", "PORT #{arrows}")
        info("WASD, LEFT SHIFT", "PORT #{3 - arrows}")
      end

      # The VIC-20's one joystick, which both sets of keys drive.
      def draw_vic20_port
        return unless draw_keys("VIC-20")

        skip
        info("ARROWS, SPACE", "JOYSTICK")
        info("WASD, LEFT SHIFT", "JOYSTICK")
      end

      # The Plus/4's two joysticks, one for each set of keys.
      def draw_plus4_ports
        return unless draw_keys("PLUS/4")

        row("SWAP JOYSTICKS", :swap)
        skip
        arrows = @controls.arrows_port
        info("ARROWS, SPACE", "JOYSTICK #{arrows}")
        info("WASD, LEFT SHIFT", "JOYSTICK #{3 - arrows}")
      end

      # The PET's keyboard, whose keys type the characters on the host's
      # (PETKeyboard), and the keys that stand for the rest of its keys.
      # The SuperPET's 6809 shows whether its keys type ASCII, or go by
      # position for the APL symbols on its keycaps.
      def draw_pet_keys
        business = @computer.model.keyboard == :business
        info("KEYBOARD", business ? "BUSINESS" : "GRAPHICS")
        draw_superpet_characters if @computer.superpet?
        (PET_KEYS + (business ? PET_BUSINESS_KEYS : PET_GRAPHICS_KEYS)).each do |line|
          @painter.text(@left, @top, line, MenuTheme::TEXT)
          @top += MenuPages::LINE
        end
      end

      def draw_superpet_characters
        apl = @computer.apl_characters?
        return unless apl || @computer.m6809_running?

        info("CHARACTERS", apl ? "APL, KEYS BY POSITION" : "ASCII")
      end

      def draw_kim1_panel
        kim = @computer
        toggle("SST", :sst, [%w[OFF ON], %i[sst_off sst_on], kim.sst ? 1 : 0])
        toggle("TTY/KB", :tty, [%w[KEYPAD TTY], %i[keypad teletype], kim.tty? ? 1 : 0])
        skip
        info("RAM", "#{kim.ram_kb}K")
        toggle("U3 PB7", :irq, [%w[OPEN IRQ], %i[irq_open irq_wired], kim.irq_wired ? 1 : 0])
        toggle("SOUND", :speaker, [["U2 PB7", "U3 PA0"], %i[pb7_out pa0_speaker], kim.speaker? ? 1 : 0])
      end

      def kim1_setting(action)
        kim = @computer
        case action
        when :sst_off, :sst_on then kim.sst = action == :sst_on
        when :keypad, :teletype
          kim.tty = action == :teletype
          kim.reset!
        when :irq_open, :irq_wired then kim.irq_wired = action == :irq_wired
        else kim.speaker = action == :pa0_speaker
        end
      end

      # What each control port has plugged in, a joystick, a mouse or
      # paddles.
      def draw_pot_ports
        toggle("PORT 1", :port1, [PORT_NAMES, PORT_ACTIONS[0], PORT_DEVICES.index(port_device(1))])
        toggle("PORT 2", :port2, [PORT_NAMES, PORT_ACTIONS[1], PORT_DEVICES.index(port_device(2))])
      end

      # The P500's two ports, its joysticks one for each set of keys, and
      # while the keys type, where its keys are.
      def draw_p500_ports
        draw_pot_ports
        return draw_cbm2_keys unless draw_keys("P500")

        row("SWAP JOYSTICKS", :swap)
        skip
        arrows = @controls.arrows_port
        info("ARROWS, SPACE", "JOYSTICK #{arrows}")
        info("WASD, LEFT SHIFT", "JOYSTICK #{3 - arrows}")
      end

      # The CBM-II's keyboard, which types as the PET's does, and the keys
      # that stand for the rest of its keys.
      def draw_cbm2_keys
        CBM2_KEYS.each do |line|
          @painter.text(@left, @top, line, MenuTheme::TEXT)
          @top += MenuPages::LINE
        end
      end

      # The toggle between the keyboard named and the joysticks, and
      # whether the keys drive the joysticks.
      def draw_keys(keyboard)
        joystick = @controls.joystick_mode?
        toggle("KEYS", :keys, [[keyboard, "JOYSTICK"], %i[keys_c64 keys_joystick], joystick ? 1 : 0])
        joystick
      end

      def keys(mode) = @controls.joystick_mode = mode == :joystick

      def port_device(port)
        index = POTS[port - 1].index(@controls.pot)
        index.nil? ? :joystick : PORT_DEVICES[index]
      end

      # Plugs the device a choice such as :port1_mouse names into its port.
      def pick_port(action)
        index = PORT_ACTIONS[0].include?(action) ? 0 : 1
        choice = PORT_ACTIONS[index].index(action)
        plug_device(index + 1, choice) unless choice.nil? || choice == PORT_DEVICES.index(port_device(index + 1))
      end

      # Plugs PORT_DEVICES[choice] into the port. A joystick there takes out
      # the pot device.
      def plug_device(port, choice)
        @controls.plug(POTS[port - 1][choice])
      end
    end
  end
end
