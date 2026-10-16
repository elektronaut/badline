# frozen_string_literal: true

module Badline
  module KernalTrap
    # Base class for the PC traps on KERNAL routines. Holds the device
    # number they answer for and the layout of the KERNAL they trap, and
    # takes its Steps around them.
    class Routine
      include IntegerHelper
      include Steps

      DEVICE = 8

      # The serial timer's high byte as ISOUR and ACPTR set it.
      ISOUR_TIMEOUT = 0x04
      ACPTR_TIMEOUT = 0x01

      def initialize(cpu:, bus:, layout:)
        @cpu = cpu
        @bus = bus
        @layout = layout
      end
    end
  end
end
