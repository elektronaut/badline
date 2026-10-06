# frozen_string_literal: true

module Badline
  class Vic20
    # What VIA 1's ports read from outside the chip. Port A carries the
    # joystick's up, down and left switches on PA2-PA4 and its fire button
    # on PA5, the line the light pen shares. The right switch is on VIA 2
    # (see KeyboardVIAPorts). Port B is the user port, with nothing plugged
    # in.
    #
    # The rest of port A belongs to the serial bus and the datasette, and
    # floats high until they are wired: PA0 and PA1 read CLK and DATA, PA6
    # the cassette sense switch, and PA7 drives ATN out. CA2 drives the
    # cassette motor, through ca2_output, and the RESTORE key pulls CA1
    # (see Vic20#press_restore).
    class UserVIAPorts
      attr_reader :joystick

      def initialize(joystick:)
        @joystick = joystick
      end

      # The joystick's up, down and left bits (0-2) move up two, and its
      # fire bit (4) up one.
      def read_a(_lines)
        bits = @joystick.port_bits
        0xc3 | ((bits & 0x07) << 2) | ((bits & 0x10) << 1)
      end

      def read_b(_lines) = 0xff
    end
  end
end
