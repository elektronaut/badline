# frozen_string_literal: true

module Badline
  class Plus4
    # The Plus/4's user port 6529 at $FD10-$FD1F, a quasi-bidirectional
    # latch: a line reads low where the latch or the outside pulls it. With
    # nothing plugged into the user port, the outside pulls only bit 2, the
    # cassette sense switch, low while a key is down on the deck. The
    # KERNAL's IRQ reads it there ($CFBF).
    class UserPort
      TAPE_SENSE = 0x04

      attr_reader :output

      def initialize(datasette)
        @datasette = datasette
        @output = 0xff
      end

      def reset!
        @output = 0xff
      end

      def peek(_addr) = @datasette.sense_low? ? @output & ~TAPE_SENSE : @output

      def poke(_addr, value)
        @output = value
      end
    end
  end
end
