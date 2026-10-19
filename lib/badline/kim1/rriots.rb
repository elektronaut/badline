# frozen_string_literal: true

module Badline
  class KIM1
    # Each 6530 a class of its own, so each keeps one type of peripheral.

    # U2, the 6530-002: the monitor's ROM, and the ports that drive the
    # keypad, the display, the teletype and the tape. Its peripheral is
    # the Panel, which hears every write to the port and direction
    # registers, so it can time how long each LED segment is lit.
    class MonitorRRIOT < Chips::RRIOT
      def reset!
        super
        @peripheral&.lines_written(port_a_output, port_b_output)
      end

      def poke(addr, value)
        super
        @peripheral.lines_written(port_a_output, port_b_output) if addr.nobits?(0x04)
      end
    end

    # U3, the 6530-003: the tape routines' ROM, and the ports the
    # application connector carries for the user, with nothing on them.
    class UserRRIOT < Chips::RRIOT
    end
  end
end
