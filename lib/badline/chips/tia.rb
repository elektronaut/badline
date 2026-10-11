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
    class TIA
      attr_reader :ports, :directions

      # What the other side drives onto each port's pins.
      attr_reader :inputs

      def initialize
        @inputs = [0, 0, 0]
        reset!
      end

      def reset!
        @ports = [0, 0, 0]
        @directions = [0, 0, 0]
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
      end
    end
  end
end
