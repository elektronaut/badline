# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's PORTS page, which MenuPages draws: what each C64
    # control port has plugged in, a joystick or a pot device, and whether
    # the keys type or drive the joysticks. The VIC-20 has one port, a
    # joystick's.
    module MenuPorts
      PORT_DEVICES = %i[joystick mouse paddles].freeze
      PORT_NAMES = %w[JOY MOUSE PADDLES].freeze
      PORT_ACTIONS = [%i[port1_joystick port1_mouse port1_paddles], %i[port2_joystick port2_mouse port2_paddles]].freeze
      POTS = [%i[none mouse1 paddles1], %i[none mouse2 paddles2]].freeze

      private

      def draw_ports
        return draw_vic20_port if @computer.family == :vic20

        toggle("PORT 1", :port1, [PORT_NAMES, PORT_ACTIONS[0], PORT_DEVICES.index(port_device(1))])
        toggle("PORT 2", :port2, [PORT_NAMES, PORT_ACTIONS[1], PORT_DEVICES.index(port_device(2))])
        return unless draw_keys("C64")

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
