# frozen_string_literal: true

require "badline/machine/ieee_drives"

module Badline
  class PET
    # The PET's true drive, a 2031, 8050 or 8250 on its IEEE-488 bus
    # (IEEEPorts), as Machine::IEEEDrives has it, at the PET's 1 MHz.
    module IEEEDrive
      include Machine::IEEEDrives

      # Settles for a snapshot, then runs on until a 2031's CPU is between
      # instructions with the PET's, as xpet saves both. It stands in for
      # Machine::Settling's, which the PET includes first.
      def settle_for_vice!
        ran = settle_for_snapshot!
        drive = @drive2031
        return ran if drive.nil?

        until ran >= Machine::Settling::LIMIT || (drive.cpu.boundary? && settled_for_snapshot?)
          cycle!
          ran += 1
        end
        ran
      end

      private

      def ieee_host_clock_hz = 1_000_000
    end
  end
end
