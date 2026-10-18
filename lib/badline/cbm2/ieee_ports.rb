# frozen_string_literal: true

module Badline
  class CBM2
    # The CBM-II's side of the IEEE-488 bus (Drives::IEEEBus): the data
    # lines DIO1-8 on the CIA's port A at $DC00, and the handshake on
    # TPI1's port A at $DE00:
    #
    #   PA3 ATN   PA4 DAV   PA5 EOI   PA6 NDAC   PA7 NRFD
    #
    # PA0-PA2 set the transceivers' directions, which follow the ports'
    # direction registers as the KERNAL sets them. Each line goes through
    # its transceiver as it is: an output bit at 0 pulls its line low, and
    # an input bit reads its line, 0 while it is low. It is TPI1's
    # peripheral, and Data the CIA's.
    #
    # The machine pushes the lines it pulls into the bus for the drives on
    # it once a cycle while a drive is on the bus (#lines_written), and
    # only when they moved.
    class IEEEPorts
      ATN = 0x08
      DAV = 0x10
      EOI = 0x20
      NDAC = 0x40
      NRFD = 0x80

      # The CIA's port A: the data lines.
      class Data
        def initialize(ports)
          @ports = ports
        end

        def read_a(_port_a, _port_b) = ~@ports.low_lines & 0xff

        def read_b(_port_a, _port_b) = 0xff

        def port_b4_high? = true
      end

      attr_reader :bus, :data

      def initialize(bus)
        @bus = bus
        @data = Data.new(self)
        @cia = nil
        @tpi = nil
        @pushed = 0
      end

      def connect(cia, tpi)
        @cia = cia
        @tpi = tpi
      end

      # TPI1's port A: the handshake lines and ATN.
      def read_a(_lines)
        low = low_lines
        value = 0xff
        value &= ~ATN if low.anybits?(Drives::IEEEBus::ATN)
        value &= ~DAV if low.anybits?(Drives::IEEEBus::DAV)
        value &= ~EOI if low.anybits?(Drives::IEEEBus::EOI)
        value &= ~NDAC if low.anybits?(Drives::IEEEBus::NDAC)
        value &= ~NRFD if low.anybits?(Drives::IEEEBus::NRFD)
        value & 0xff
      end

      def read_b(_lines) = 0xff

      def read_c(_lines) = 0xff

      # The lines low on the bus.
      def low_lines = @bus.low_lines(controller_lines)

      # The drives on the bus see the lines the machine pulls now, if they
      # moved.
      def lines_written
        lines = controller_lines
        push(lines) unless lines == @pushed
      end

      # The drives on the bus see the lines the machine pulls now.
      def push_lines = push(controller_lines)

      private

      def push(lines)
        @pushed = lines
        @bus.host_lines = lines
      end

      # The lines the machine pulls low.
      def controller_lines
        low = ~@cia.port_a_lines & Drives::IEEEBus::DIO
        port_a = @tpi.port_a_output
        low |= Drives::IEEEBus::ATN if port_a.nobits?(ATN)
        low |= Drives::IEEEBus::DAV if port_a.nobits?(DAV)
        low |= Drives::IEEEBus::EOI if port_a.nobits?(EOI)
        low |= Drives::IEEEBus::NDAC if port_a.nobits?(NDAC)
        low |= Drives::IEEEBus::NRFD if port_a.nobits?(NRFD)
        low
      end
    end
  end
end
