# frozen_string_literal: true

module Badline
  class Vic20
    # The datasette and the serial bus, wired to the VIAs.
    #
    # The serial bus's lines go out through inverters, so an output that
    # drives high pulls its line low: ATN from VIA 1's PA7, the clock from
    # VIA 2's CA2 and the data line from VIA 2's CB2. An output left as an
    # input floats high, and pulls its line too, as after a reset. CLK and
    # DATA come back on VIA 1's PA0 and PA1 (UserVIAPorts). The machine
    # pushes the lines it pulls into the bus, as the C64's CIA 2 port A
    # bits, after each write to a VIA that moves them.
    #
    # The datasette's read line pulses VIA 2's CA1, its sense switch reads
    # on VIA 1's PA6, its motor runs while VIA 1's CA2 is low, and VIA 2's
    # PB3 drives its write line, the same pin as a keyboard column.
    module PortWiring
      # The lines the machine pulls, as IECBus host lines.
      def serial_lines
        lines = 0
        lines |= IECBus::HOST_ATN_OUT if @via1.port_a_output.anybits?(0x80)
        lines |= IECBus::HOST_CLK_OUT if @via2.ca2_output
        lines |= IECBus::HOST_DATA_OUT if @via2.cb2_output
        lines
      end

      private

      def wire_ports
        @datasette.on_flag { tape_pulse }
        @bus.on_via_write { via_written }
        via_written
      end

      def via_written
        lines = serial_lines
        @iec_bus.host_lines = lines unless lines == @iec_bus.host_lines
        @datasette.motor = !@via1.ca2_output
        @datasette.write_line = @via2.port_b_output.anybits?(0x08)
      end

      # A falling edge on the read line, and the line back up.
      def tape_pulse
        @via2.ca1 = false
        @via2.ca1 = true
      end
    end
  end
end
