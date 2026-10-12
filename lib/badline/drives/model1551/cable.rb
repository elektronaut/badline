# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # TCBM, the cable between the 1551's TIA and the 6523 TIA in its
      # interface in the computer's expansion port (zimmers.net's 1551
      # memory map, schematic 251860):
      #
      # - the eight data lines join the two port As;
      # - the drive's STATUS0 and STATUS1 (PC0-1) reach the computer's PB0-1;
      # - the drive's ACK (PC3) reaches the computer's PC7;
      # - the computer's DAV (PC6) reaches the drive's PC7.
      #
      # The drive pulls every line up, so a line neither side drives low
      # reads 1. The computer's other port B and C pins read 0. Every write
      # to either TIA moves the lines at once.
      class Cable
        STATUS = 0x03
        ACK = 0x08
        DAV = 0x40

        attr_reader :host, :drive

        # Plugs the cable into +host+, the computer's Chips::TIA, and
        # +drive+, the drive's (Model1551::TIA#chip).
        def initialize(host, drive)
          @host = host
          @drive = drive
          host.cable = self
          drive.cable = self
          moved
        end

        # Pulls the cable out: the computer's TIA reads 0 on every input and
        # the drive's lines float high.
        def unplug
          @host.cable = nil
          @drive.cable = nil
          host_inputs = @host.inputs
          drive_inputs = @drive.inputs
          3.times do |port|
            host_inputs[port] = 0
            drive_inputs[port] = 0xff
          end
        end

        # Either side wrote its TIA: the lines settle again.
        def moved
          host = @host
          drive = @drive
          data = host.output(0) & drive.output(0)
          drive_lines = drive.output(2)
          host_lines = host.output(2)
          host_inputs = host.inputs
          host_inputs[0] = data
          host_inputs[1] = drive_lines & STATUS
          host_inputs[2] = ((drive_lines & ACK) << 4) | (host_lines & DAV)
          drive_inputs = drive.inputs
          drive_inputs[0] = data
          drive_inputs[2] = (drive_inputs[2] & 0x7f) | ((host_lines & DAV) << 1)
        end
      end
    end
  end
end
