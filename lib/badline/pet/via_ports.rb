# frozen_string_literal: true

module Badline
  class PET
    # What the VIA's ports read from outside the chip. Port B's PB5 is the
    # vertical drive line, low in the retrace, and PB0, PB6 and PB7 read
    # the IEEE-488 bus's NDAC, NRFD and DAV (IEEEPorts). The user port on
    # port A floats high.
    class VIAPorts
      def initialize(machine)
        @machine = machine
      end

      def read_a(_lines) = 0xff

      def read_b(_lines) = @machine.ieee.via_inputs & (@machine.vertical_drive? ? 0xff : 0xdf)
    end
  end
end
