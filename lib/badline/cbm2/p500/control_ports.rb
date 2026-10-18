# frozen_string_literal: true

module Badline
  class CBM2
    class P500
      # The P500's two control ports on the CIA at $DC00, as its schematic's
      # game port interface wires them (sheets 9 and 10): port 1's
      # directions on PB0-PB3 and its fire button on PA6, which is the VIC's
      # light pen input too, and port 2's on PB4-PB7 and PA7. Every switch
      # pulls its line low. Port A carries the IEEE-488 bus's data lines as
      # well (IEEEPorts::Data), which pull it low too.
      #
      # A device on a port, a pair of paddles or a mouse, adds its buttons
      # to the port's lines, and its pots reach the SID through the analog
      # switches PA0 (port 1) and PA1 (port 2) close, as PA6 and PA7 do on
      # the C64 (Input::ControlPorts).
      class ControlPorts
        DIRECTIONS = 0x0f
        FIRE = 0x10
        PORT1_POTS = 0x01
        PORT2_POTS = 0x02

        attr_reader :joystick1, :joystick2
        attr_accessor :device1, :device2

        def initialize(joystick1, joystick2, ieee)
          @joystick1 = joystick1
          @joystick2 = joystick2
          @ieee = ieee
          @device1 = nil
          @device2 = nil
          @cia = nil
        end

        # The CIA whose PA0 and PA1 close the pots' switches.
        def connect(cia)
          @cia = cia
        end

        def read_a(port_a, port_b)
          fire1 = port1.anybits?(FIRE) ? 0x40 : 0
          fire2 = port2.anybits?(FIRE) ? 0x80 : 0
          (0x3f | fire1 | fire2) & @ieee.read_a(port_a, port_b)
        end

        def read_b(_port_a, _port_b)
          (port1 & DIRECTIONS) | ((port2 & DIRECTIONS) << 4)
        end

        # PB4 is port 2's up line here, not a light pen input.
        def port_b4_high? = true

        # Whether port 1's fire line is high, the light pen input's.
        def fire1_high? = port1.anybits?(FIRE)

        def pot_x = selected_devices.map(&:pot_x).min || 0xff

        def pot_y = selected_devices.map(&:pot_y).min || 0xff

        private

        def port1 = port_bits(@joystick1, @device1)

        def port2 = port_bits(@joystick2, @device2)

        def port_bits(joystick, device)
          device ? joystick.port_bits & device.port_bits : joystick.port_bits
        end

        def selected_devices
          lines = @cia&.port_a_lines || 0x00
          devices = []
          devices << @device1 if @device1 && lines.anybits?(PORT1_POTS)
          devices << @device2 if @device2 && lines.anybits?(PORT2_POTS)
          devices
        end
      end
    end
  end
end
