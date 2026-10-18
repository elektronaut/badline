# frozen_string_literal: true

module Badline
  module Drives
    class Model2031
      # VIA 1's side of the IEEE-488 bus (Drives::IEEEBus), through a 75160
      # for the data lines and a 75161 for the control lines (schematic
      # 2031038, sheet 2):
      #
      #   PA0-7  DIO1-8                   PB4  T/R, high to talk
      #   PB0    ATN acknowledge (ATNA)   PB5  HD SEL, unused
      #   PB1    NRFD                     PB6  DAV
      #   PB2    NDAC                     PB7  ATN in, high while ATN is low
      #   PB3    EOI                      CA1  ATN in, as PB7
      #
      # The ports read and drive the lines' levels, 0 for a low line. T/R
      # turns the transceivers: talking, the drive drives the data lines,
      # DAV and EOI, and reads NRFD and NDAC; listening, the other way round.
      # EOI turns back to the bus while ATN is low. A pin the transceiver
      # drives the bus from reads the drive's own side, high but for what
      # the VIA or a jumper pulls low.
      #
      # An XOR of ATN in and ATNA drives two 7406s that pull NRFD and NDAC
      # low on the bus, so the drive answers ATN before the DOS gets to it,
      # and holds the bus until the DOS acknowledges. ATNA reaches the XOR
      # only while PB0 is an output, and is low there otherwise, which
      # leaves the bus alone while the DOS reads the jumpers.
      #
      # The device number jumpers are diodes from PB0 and PB1 to CA2: with
      # CA2 low, a fitted diode pulls its line low, and the DOS reads the
      # device number off the two at reset, 8 with both fitted. Lifting the
      # one on PB0 adds 1, and the one on PB1 2.
      #
      # The drive takes the controller's lines a host cycle late, as the
      # serial drives do (Engine::SerialLines): latch_host takes them at the
      # end of each host cycle.
      class IEEEPort
        ATNA = 0x01
        NRFD = 0x02
        NDAC = 0x04
        EOI = 0x08
        TALK = 0x10
        DAV = 0x40
        ATN_IN = 0x80

        attr_reader :bus

        # The lines the controller pulled, as latch_host took them.
        attr_reader :host

        def initialize(device:, bus:)
          raise ArgumentError, "a 2031 is device 8 to 11, not #{device}" unless device.between?(8, 11)

          @diodes = ~(device - 8) & 0x03
          @via = nil
          @host = 0
          self.bus = bus
        end

        # The drive's VIA 1, whose outputs it drives the bus with.
        attr_writer :via

        def bus=(bus)
          @bus = bus
          latch_host
        end

        # Takes the controller's lines for the drive cycles of the next host
        # cycle.
        def latch_host
          @host = @bus.host_lines
        end

        # Whether the controller has moved ATN since the last latch_host.
        def atn_moved? = (@bus.host_lines ^ @host).anybits?(IEEEBus::ATN)

        def atn_low? = @host.anybits?(IEEEBus::ATN)

        # The data lines, while the transceiver listens.
        def read_a(_lines) = talking? ? 0xff : ~@bus.low_lines(@host) & 0xff

        # The control lines the transceiver turns towards the drive, and
        # ATN.
        def read_b(_lines)
          low = @bus.low_lines(@host)
          value = 0x7f
          if talking?
            value &= ~NRFD if low.anybits?(IEEEBus::NRFD)
            value &= ~NDAC if low.anybits?(IEEEBus::NDAC)
            value &= ~EOI if low.anybits?(IEEEBus::EOI) && low.anybits?(IEEEBus::ATN)
          else
            value &= ~EOI if low.anybits?(IEEEBus::EOI)
            value &= ~DAV if low.anybits?(IEEEBus::DAV)
          end
          value |= ATN_IN if low.anybits?(IEEEBus::ATN)
          value & jumpers
        end

        # The lines the drive pulls low while ATN is low or not, as bus bits.
        def ieee_low_lines(atn)
          via = @via
          lines = via.port_b_output & jumpers
          low = 0
          if lines.anybits?(TALK)
            low |= ~via.port_a_output & IEEEBus::DIO
            low |= IEEEBus::DAV if lines.nobits?(DAV)
            low |= IEEEBus::EOI if lines.nobits?(EOI) && !atn
          else
            low |= IEEEBus::NRFD if lines.nobits?(NRFD)
            low |= IEEEBus::NDAC if lines.nobits?(NDAC)
          end
          low |= IEEEBus::NRFD | IEEEBus::NDAC if atn != (lines & via.port_b_directions).anybits?(ATNA)
          low
        end

        # The controller's lines as the port latched them, under `prefix`.
        def save_fields(out, prefix) = out.int("#{prefix}host", @host)

        def load_fields(input, prefix)
          @host = input.int("#{prefix}host", @host)
        end

        private

        def talking? = @via.port_b_output.anybits?(TALK)

        # PB0 and PB1 as the jumper diodes leave them: pulled low through
        # each fitted one while CA2 is low.
        def jumpers = @via.ca2_output ? 0xff : ~@diodes & 0xff
      end
    end
  end
end
