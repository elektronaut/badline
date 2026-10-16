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
      # - the computer's DAV (PC6) reaches the drive's PC7;
      # - the drive's DEV (PC2) picks the interface's address (Model1551).
      #
      # The drive pulls every line up, so a line neither side drives low
      # reads 1. The computer's other port B and C pins read 0.
      #
      # The computer sees the drive's lines as soon as the drive writes
      # them. The drive sees the computer's a host cycle late, as the
      # cable latched them at the end of the last (latch_host), as a drive
      # on the serial bus sees ATN: the cable is the 1551's serial port to
      # Drives::Engine::Core, and a write that moves the computer's lines
      # wakes a drive asleep in its idle loop (atn_moved?).
      class Cable
        STATUS = 0x03
        DEV = 0x04
        ACK = 0x08
        DAV = 0x40

        attr_reader :host, :drive

        # Plugs the cable into +host+, the computer's Chips::TIA, and
        # +drive+, the drive's (Model1551::TIA#chip), for +unit+, the drive.
        def initialize(host, drive, unit)
          @host = host
          @drive = drive
          @unit = unit
          @data = 0xff
          @dav = DAV
          @moved = false
          host.cable = self
          drive.cable = self
          relatch
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

        # Whether the computer moved its lines since latch_host.
        def atn_moved? = @moved

        # Takes the computer's lines for the drive's cycles in the next host
        # cycle.
        def latch_host
          return unless @moved

          @moved = false
          relatch
        end

        # Takes the computer's lines as they stand, as a snapshot leaves
        # them.
        def relatch
          host = @host
          @data = host.output(0)
          @dav = host.output(2) & DAV
          @moved = false
          moved
        end

        # Either side wrote its TIA: the computer's inputs follow the drive
        # at once, and the drive's follow the lines last latched.
        def moved
          host = @host
          drive = @drive
          drive_data = drive.output(0)
          drive_lines = drive.output(2)
          host_lines = host.output(2)
          host_data = host.output(0)
          host_inputs = host.inputs
          host_inputs[0] = host_data & drive_data
          host_inputs[1] = drive_lines & STATUS
          host_inputs[2] = ((drive_lines & ACK) << 4) | (host_lines & DAV)
          drive_inputs = drive.inputs
          drive_inputs[0] = @data & drive_data
          drive_inputs[2] = (drive_inputs[2] & 0x7f) | (@dav << 1)
          @unit.dev_line(drive_lines.anybits?(DEV))
          return if @moved || (host_data == @data && (host_lines & DAV) == @dav)

          @moved = true
          @unit.host_written!
        end
      end
    end
  end
end
