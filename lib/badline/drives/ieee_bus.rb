# frozen_string_literal: true

module Badline
  module Drives
    # The IEEE-488 bus between a PET and its drives: eight data lines, DIO1
    # to DIO8, and the control lines EOI, DAV, NRFD, NDAC and ATN, each open
    # collector and active low, so a line is low while anything on the bus
    # pulls it low. The PET is the controller and always on the bus, and
    # reads back every line it drives.
    #
    # No device plugs in yet, so the lines carry the controller's levels
    # alone: nobody answers a handshake, and the KERNAL reports DEVICE NOT
    # PRESENT for every device the traps don't serve.
    class IEEEBus
      # The lines as bits, the data lines in the low byte, DIO1 in bit 0.
      DIO = 0x00ff
      EOI = 0x0100
      DAV = 0x0200
      NRFD = 0x0400
      NDAC = 0x0800
      ATN = 0x1000

      # The lines low on the bus while the controller pulls the lines in
      # +controller+ low.
      def low_lines(controller) = controller
    end
  end
end
