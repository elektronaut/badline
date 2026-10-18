# frozen_string_literal: true

module Badline
  class PET
    # The PET's side of the IEEE-488 bus (Drives::IEEEBus), spread over
    # three chips:
    #
    #   PIA 2 port A  DIO1-8 in        PIA 2 port B  DIO1-8 out
    #   PIA 2 CA2     NDAC out         PIA 2 CB2     DAV out
    #   PIA 1 PA6     EOI in           PIA 1 CA2     EOI out
    #   VIA PB0       NDAC in          VIA PB1       NRFD out
    #   VIA PB6       NRFD in          VIA PB2       ATN out
    #   VIA PB7       DAV in
    #
    # The outputs go through inverting drivers onto the bus, so a 0 on a
    # data line's port bit pulls the line low, and the inputs read the
    # lines as they are, a 0 for a low line. It is PIA 2's peripheral, and
    # answers what PIA 1 and the VIA read of the bus. It pushes the lines
    # the PET pulls into the bus for the drives on it after every write to
    # the chips (lines_written).
    class IEEEPorts
      attr_reader :bus

      def initialize(bus)
        @bus = bus
        @pia1 = @pia2 = @via = nil
      end

      def connect(pia1, pia2, via)
        @pia1 = pia1
        @pia2 = pia2
        @via = via
      end

      # The data lines.
      def read_a(_lines) = ~low_lines & 0xff

      def read_b(_lines) = 0xff

      # PIA 1's PA6 reads EOI.
      def eoi_input = low_lines.anybits?(Drives::IEEEBus::EOI) ? 0xbf : 0xff

      # The VIA's PB0, PB6 and PB7 read NDAC, NRFD and DAV.
      def via_inputs
        low = low_lines
        value = 0xff
        value &= 0xfe if low.anybits?(Drives::IEEEBus::NDAC)
        value &= 0xbf if low.anybits?(Drives::IEEEBus::NRFD)
        value &= 0x7f if low.anybits?(Drives::IEEEBus::DAV)
        value
      end

      # The PET wrote one of its chips: the drives on the bus see the lines
      # it pulls now.
      def lines_written
        bus = @bus
        bus.host_lines = controller_lines unless bus.drives.empty?
      end

      # The drives on the bus see the lines the PET pulls now.
      def push_lines = lines_written

      # Nothing to push once a cycle: the PET pushes its lines as its chips
      # are written.
      def cycle_lines = nil

      private

      def low_lines = @bus.low_lines(controller_lines)

      # The lines the PET pulls low.
      def controller_lines
        low = ~@pia2.port_b_output & Drives::IEEEBus::DIO
        low |= Drives::IEEEBus::EOI unless @pia1.ca2_output
        low |= Drives::IEEEBus::NDAC unless @pia2.ca2_output
        low |= Drives::IEEEBus::DAV unless @pia2.cb2_output
        port_b = @via.port_b_output
        low |= Drives::IEEEBus::NRFD if port_b.nobits?(0x02)
        low |= Drives::IEEEBus::ATN if port_b.nobits?(0x04)
        low
      end
    end
  end
end
