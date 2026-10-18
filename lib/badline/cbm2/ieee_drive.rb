# frozen_string_literal: true

require "badline/machine/ieee_drives"

module Badline
  class CBM2
    # The CBM-II's true drive, a 2031, 8050 or 8250 on its IEEE-488 bus
    # (IEEEPorts), as Machine::IEEEDrives has it, at the machine's clock:
    # 2 MHz on the B series, the VIC-II's on the P500. Both include it.
    module IEEEDrive
      include Machine::IEEEDrives

      private

      def ieee_host_clock_hz = timing.clock_hz
    end
  end
end
