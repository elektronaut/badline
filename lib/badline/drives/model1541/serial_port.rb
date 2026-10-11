# frozen_string_literal: true

module Badline
  class Drive1541
    # What VIA 1's ports read from outside the chip. Port B carries the
    # serial bus inputs and the device number jumpers (Drive::SerialLines);
    # port A goes to the unused parallel header and floats high.
    class SerialPort
      include Drive::SerialLines

      def initialize(device: 8, bus: IECBus.new)
        init_serial_lines(device, bus)
      end

      def read_a(_lines) = 0xff
    end
  end
end
