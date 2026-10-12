# frozen_string_literal: true

module Badline
  class Plus4
    # The Plus/4's user port 6529 at $FD10-$FD1F, a quasi-bidirectional
    # latch: a line reads low where the latch or the outside pulls it. With
    # nothing plugged into the user port, the outside pulls only bit 2, the
    # cassette sense switch, low while a key is down on the deck. The
    # KERNAL's IRQ reads it there ($CFBF), and takes P1 as RS-232's clear
    # to send, sending through the ACIA only while it reads high.
    #
    # A device on the user port drives P0-P7 through #inputs, low where its
    # bit is clear.
    class UserPort
      TAPE_SENSE = 0x04

      attr_reader :output
      attr_accessor :inputs

      def initialize(datasette)
        @datasette = datasette
        @output = 0xff
        @inputs = 0xff
      end

      def reset!
        @output = 0xff
      end

      def peek(_addr)
        lines = @output & @inputs
        @datasette.sense_low? ? lines & ~TAPE_SENSE : lines
      end

      def poke(_addr, value)
        @output = value
      end
    end
  end
end
