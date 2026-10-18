# frozen_string_literal: true

require "badline/machine/ieee_drives"

module Badline
  class PET
    # The PET's true drive, a 2031, 8050 or 8250 on its IEEE-488 bus
    # (IEEEPorts), as Machine::IEEEDrives has it, at the PET's 1 MHz.
    module IEEEDrive
      include Machine::IEEEDrives

      # Settles for a snapshot, then runs on until a 2031's CPU, or an
      # 8050's interface processor with its controller at the start of its
      # idle loop, is between instructions with the PET's, as xpet saves
      # them, or for so many cycles, then on to the PET's next instruction.
      # It stands in for Machine::Settling's, which the PET includes first.
      def settle_for_vice!
        ran = settle_for_snapshot!
        return ran if @drive2031.nil? && @drive8050.nil?

        until ran >= Machine::Settling::LIMIT || (drive_settled_for_vice? && settled_for_snapshot?)
          cycle!
          ran += 1
        end
        ran + settle_for_snapshot!
      end

      # Whether the true drive is where xpet saves it (#settle_for_vice!).
      def drive_settled_for_vice?
        return @drive2031.cpu.boundary? if @drive2031

        fdc = @drive8050.fdc_cpu
        @drive8050.ip_cpu.boundary? && fdc.boundary? && fdc.program_counter == Badline::Drives::Model8050::Idle::FDC_LOOP
      end

      private

      def ieee_host_clock_hz = 1_000_000
    end
  end
end
