# frozen_string_literal: true

module Badline
  class Drive1541
    # What VIA 1's ports read from outside the chip. Port B carries the
    # serial bus inputs and the device number jumpers; port A goes to the
    # unused parallel header and floats high.
    #
    # DATA IN (PB0), CLK IN (PB2) and ATN IN (PB7) come through inverters,
    # so a released line reads 0. Nothing drives the serial bus yet, so all
    # three read released. The jumpers on PB5 and PB6 pull a line low when
    # closed, and both closed make device 8.
    class SerialPort
      SERIAL_INPUTS = 0b1000_0101
      JUMPERS = 0b0110_0000

      def initialize(device: 8)
        @port_b = (0xff & ~(SERIAL_INPUTS | JUMPERS)) | (((device - 8) & 0x03) << 5)
      end

      def read_a(_lines) = 0xff

      def read_b(_lines) = @port_b
    end
  end
end
