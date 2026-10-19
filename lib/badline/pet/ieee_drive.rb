# frozen_string_literal: true

require "badline/machine/ieee_drives"

module Badline
  class PET
    # The PET's true drive, a 2031, 8050 or 8250 on its IEEE-488 bus
    # (IEEEPorts), as Machine::IEEEDrives has it, at the PET's 1 MHz.
    module IEEEDrive
      include Machine::IEEEDrives

      private

      def ieee_host_clock_hz = 1_000_000
    end
  end
end
