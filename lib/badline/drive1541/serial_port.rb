# frozen_string_literal: true

module Badline
  class Drive1541
    # What VIA 1's ports read from outside the chip. Port B carries the
    # serial bus inputs and the device number jumpers; port A goes to the
    # unused parallel header and floats high.
    #
    # DATA IN (PB0), CLK IN (PB2) and ATN IN (PB7) come through inverters,
    # so a released line reads 0 and a pulled one 1. The jumpers on PB5 and
    # PB6 pull a line low when closed, and both closed make device 8.
    class SerialPort
      DATA_IN = 0x01
      CLK_IN = 0x04
      ATN_IN = 0x80
      SERIAL_INPUTS = DATA_IN | CLK_IN | ATN_IN
      JUMPERS = 0b0110_0000

      attr_accessor :bus

      def initialize(device: 8, bus: nil)
        @port_b = (0xff & ~(SERIAL_INPUTS | JUMPERS)) | (((device - 8) & 0x03) << 5)
        @bus = bus
      end

      def read_a(_lines) = 0xff

      def read_b(_lines)
        low = @bus.low_lines
        value = @port_b
        value |= DATA_IN if low.anybits?(IECBus::DATA)
        value |= CLK_IN if low.anybits?(IECBus::CLK)
        value |= ATN_IN if low.anybits?(IECBus::ATN)
        value
      end
    end
  end
end
