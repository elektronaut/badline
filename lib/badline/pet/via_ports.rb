# frozen_string_literal: true

module Badline
  class PET
    # What the VIA's ports read from outside the chip. Port B's PB5 is the
    # vertical drive line, low in the retrace. The IEEE-488 lines it reads,
    # NDAC on PB0, NRFD on PB6 and DAV on PB7, float high with nothing on
    # the bus, as does the user port on port A.
    class VIAPorts
      def initialize(machine)
        @machine = machine
      end

      def read_a(_lines) = 0xff

      def read_b(_lines) = @machine.vertical_drive? ? 0xff : 0xdf
    end
  end
end
