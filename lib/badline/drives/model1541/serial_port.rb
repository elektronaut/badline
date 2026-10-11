# frozen_string_literal: true

module Badline
  module Drives
    class Model1541
      # What VIA 1's ports read from outside the chip. Port B carries the
      # serial bus inputs and the device number jumpers (Drives::Engine::SerialLines);
      # port A goes to the unused parallel header and floats high.
      class SerialPort
        include Engine::SerialLines

        def initialize(device: 8, bus: SerialBus.new)
          init_serial_lines(device, bus)
        end

        def read_a(_lines) = 0xff
      end
    end
  end
end
