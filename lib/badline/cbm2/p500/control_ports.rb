# frozen_string_literal: true

module Badline
  class CBM2
    class P500
      # The P500's two control ports on the CIA at $DC00, as its schematic's
      # game port interface wires them: port 1's directions on PB0-PB3 and
      # its fire button on PA6, port 2's on PB4-PB7 and PA7. Every switch
      # pulls its line low.
      class ControlPorts
        DIRECTIONS = 0x0f
        FIRE = 0x10

        attr_reader :joystick1, :joystick2

        def initialize(joystick1, joystick2)
          @joystick1 = joystick1
          @joystick2 = joystick2
        end

        def read_a(_port_a, _port_b)
          fire1 = @joystick1.port_bits.anybits?(FIRE) ? 0x40 : 0
          fire2 = @joystick2.port_bits.anybits?(FIRE) ? 0x80 : 0
          0x3f | fire1 | fire2
        end

        def read_b(_port_a, _port_b)
          (@joystick1.port_bits & DIRECTIONS) | ((@joystick2.port_bits & DIRECTIONS) << 4)
        end

        # PB4 is port 2's up line here, not a light pen input.
        def port_b4_high? = true
      end
    end
  end
end
