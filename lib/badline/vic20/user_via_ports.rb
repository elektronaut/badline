# frozen_string_literal: true

module Badline
  class Vic20
    # What VIA 1's ports read from outside the chip. Port A carries the
    # serial bus's CLK and DATA on PA0 and PA1, which read 1 while a line
    # is released, the joystick's up, down and left switches on PA2-PA4,
    # its fire button on PA5, the line the light pen shares, and the
    # cassette sense switch on PA6, low while a key is down on the deck.
    # The right switch is on VIA 2 (see KeyboardVIAPorts). PA7 drives ATN
    # out and reads back what it drives. Port B is the user port, with
    # nothing plugged in.
    #
    # CA2 drives the cassette motor, which runs while CA2 is low, and the
    # RESTORE key pulls CA1 (see Vic20#press_restore).
    class UserVIAPorts
      attr_reader :joystick

      def initialize(joystick:, serial_bus:, datasette:)
        @joystick = joystick
        @serial_bus = serial_bus
        @datasette = datasette
      end

      # The joystick's up, down and left bits (0-2) move up two, and its
      # fire bit (4) up one.
      def read_a(_lines)
        bits = @joystick.port_bits
        value = 0x80 | ((bits & 0x07) << 2) | ((bits & 0x10) << 1)
        value |= 0x40 unless @datasette.sense_low?
        value | serial_inputs
      end

      def read_b(_lines) = 0xff

      private

      def serial_inputs
        low = @serial_bus.low_lines
        value = 0x03
        value &= ~0x01 if low.anybits?(IECBus::CLK)
        value &= ~0x02 if low.anybits?(IECBus::DATA)
        value
      end
    end
  end
end
