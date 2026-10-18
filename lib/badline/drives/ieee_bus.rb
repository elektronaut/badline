# frozen_string_literal: true

module Badline
  module Drives
    # The IEEE-488 bus between a PET and its drives: eight data lines, DIO1
    # to DIO8, and the control lines EOI, DAV, NRFD, NDAC and ATN, each open
    # collector and active low, so a line is low while anything on the bus
    # pulls it low. The PET is the controller and always on the bus, and
    # reads back every line it drives.
    #
    # The controller pushes the lines it pulls whenever they may have moved
    # (host_lines=), and the bus holds them for the drives, which take them
    # a host cycle late. Each drive on the bus answers the lines it pulls
    # (ieee_low_lines) while ATN is or isn't low, from its own outputs, which
    # hold still while it sleeps. With no drive on the bus nobody answers a
    # handshake, and the KERNAL reports DEVICE NOT PRESENT for every device
    # the traps don't serve.
    class IEEEBus
      # The lines as bits, the data lines in the low byte, DIO1 in bit 0.
      DIO = 0x00ff
      EOI = 0x0100
      DAV = 0x0200
      NRFD = 0x0400
      NDAC = 0x0800
      ATN = 0x1000

      # The lines the controller last pushed.
      attr_reader :host_lines

      attr_reader :drives

      def initialize
        @drives = []
        @host_lines = 0
      end

      # The controller pushes the lines it pulls, and the drives look at
      # them again.
      def host_lines=(lines)
        @host_lines = lines
        drives = @drives
        i = 0
        while i < drives.length
          drives[i].host_written!
          i += 1
        end
      end

      def attach(drive)
        @drives << drive unless @drives.include?(drive)
      end

      def detach(drive)
        @drives.delete(drive)
      end

      # The lines low on the bus while the controller pulls the lines in
      # +controller+ low.
      def low_lines(controller)
        low = controller
        drives = @drives
        return low if drives.empty?

        atn = controller.anybits?(ATN)
        i = 0
        while i < drives.length
          low |= drives[i].ieee_low_lines(atn)
          i += 1
        end
        low
      end
    end
  end
end
