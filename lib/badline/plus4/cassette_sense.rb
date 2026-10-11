# frozen_string_literal: true

module Badline
  class Plus4
    # The C16's and C116's cassette sense, which has no 6529 to go through:
    # a read of $FD10-$FD1F enables a 74LS125 that drives the sense line
    # onto data bit 2, low while a key is down on the deck (C16 schematic
    # 251788, sheet 1, U11). Nothing drives the other bits, which keep the
    # last byte on the bus, and a write goes nowhere.
    class CassetteSense
      TAPE_SENSE = 0x04

      def initialize(datasette)
        @datasette = datasette
      end

      # The byte a read finds, from +data+, the last byte on the bus.
      def read(data) = @datasette.sense_low? ? data & ~TAPE_SENSE : data | TAPE_SENSE
    end
  end
end
