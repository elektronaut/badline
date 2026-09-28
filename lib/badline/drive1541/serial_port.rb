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
    #
    # The drive sees the C64's side of the bus a host cycle late. The C64's
    # CIA changes its pins at the end of the cycle that writes them, and
    # the drive's VIA samples its own late in each of its cycles, so a
    # drive cycle that runs alongside the write reads the lines from
    # before it. The drive runs after the C64 in each host cycle (see
    # Computer#cycle!), so the port reads the C64's lines as latch_host
    # took them at the end of the last one. Fast loaders that time their
    # transfer from an ATN edge, as VICE's drive tests do, depend on it.
    class SerialPort
      DATA_IN = 0x01
      CLK_IN = 0x04
      ATN_IN = 0x80
      SERIAL_INPUTS = DATA_IN | CLK_IN | ATN_IN
      JUMPERS = 0b0110_0000

      attr_reader :bus

      def initialize(device: 8, bus: nil)
        @port_b = (0xff & ~(SERIAL_INPUTS | JUMPERS)) | (((device - 8) & 0x03) << 5)
        @host = 0
        self.bus = bus
      end

      def bus=(bus)
        @bus = bus
        latch_host
      end

      # Takes the C64's lines as they stand, for the drive cycles of the
      # next host cycle.
      def latch_host
        @host = @bus ? @bus.host_lines : 0
      end

      def atn_low? = @bus.atn_low?(@host)

      def read_a(_lines) = 0xff

      def read_b(_lines)
        low = @bus.low_lines(@host)
        value = @port_b
        value |= DATA_IN if low.anybits?(IECBus::DATA)
        value |= CLK_IN if low.anybits?(IECBus::CLK)
        value |= ATN_IN if low.anybits?(IECBus::ATN)
        value
      end
    end
  end
end
