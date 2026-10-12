# frozen_string_literal: true

module Badline
  module Chips
    # The 6523 TIA, a tri-port interface adapter: three 8-bit ports, A, B
    # and C at registers 0-2, each with its direction register at 3-5, a 1
    # making the pin an output. Its three address lines repeat the
    # registers every 8 bytes, and registers 6 and 7 read $FF.
    #
    # A pin read as an output returns what the port drives, and one read as
    # an input returns what the other side drives, #inputs, per port.
    #
    # A cable plugged in (Drives::Model1551::Cable) hears every write and
    # reset, which can move the pins it carries.
    class TIA
      attr_reader :ports, :directions

      # What the other side drives onto each port's pins.
      attr_reader :inputs

      # The cable to the other side, or nil.
      attr_accessor :cable

      def initialize
        @inputs = [0, 0, 0]
        @cable = nil
        reset!
      end

      def reset!
        @ports = [0, 0, 0]
        @directions = [0, 0, 0]
        @cable&.moved
      end

      def peek(addr)
        register = addr & 0x07
        return 0xff if register > 5
        return @directions[register - 3] if register >= 3

        direction = @directions[register]
        (@ports[register] & direction) | (@inputs[register] & ~direction & 0xff)
      end

      def poke(addr, value)
        register = addr & 0x07
        return if register > 5

        if register >= 3
          @directions[register - 3] = value
        else
          @ports[register] = value
        end
        @cable&.moved
      end

      # The levels on +port+'s pins as the chip leaves them: an output's
      # level, and 1 for an input, which the chip doesn't drive.
      def output(port)
        direction = @directions[port]
        (@ports[port] & direction) | (~direction & 0xff)
      end

      # The ports, their directions and what the other side drives, in a
      # keyed snapshot module (Snapshot::Keyed, BL-TIA1 and BL-TIA2).
      def save_fields(out)
        out.ints("ports", @ports).ints("directions", @directions).ints("inputs", @inputs)
      end

      def load_fields(input)
        input.ints_into("ports", @ports)
        input.ints_into("directions", @directions)
        input.ints_into("inputs", @inputs)
      end
    end
  end
end
