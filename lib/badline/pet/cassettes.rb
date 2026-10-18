# frozen_string_literal: true

module Badline
  class PET
    # The PET's two cassette ports, each with a datasette:
    #
    #             read       motor, low runs it   sense, low with a key down
    #   #1        PIA 1 CA1  PIA 1 CB2            PIA 1 PA4
    #   #2        VIA CB1    VIA PB4              PIA 1 PA5
    #
    # Both record from VIA PB3. The KERNAL reads each tape as the falling
    # edges its read line makes, as the C64 and VIC-20 do. The machine
    # passes the motor and write lines on after each write to the I/O
    # chips (#lines_written), and clocks the decks only while a tape runs
    # (#running?).
    class Cassettes
      attr_reader :datasette1, :datasette2

      def initialize(pia1, via)
        @pia1 = pia1
        @via = via
        @datasette1 = Drives::Datasette.new
        @datasette2 = Drives::Datasette.new
        @datasette1.on_flag { pulse1 }
        @datasette2.on_flag { pulse2 }
        @running = false
        @running_handler = nil
        @datasette1.on_running_change { update_running }
        @datasette2.on_running_change { update_running }
      end

      # Whether either deck's tape runs.
      def running? = @running

      # Whether either deck's tape runs, each time that changes.
      def on_running_change(&handler)
        @running_handler = handler
      end

      def cycle!
        @datasette1.cycle!
        @datasette2.cycle!
      end

      # PA4 and PA5 of PIA 1's port A, low for a deck with a key down.
      def sense_input
        value = 0xff
        value &= 0xef if @datasette1.sense_low?
        value &= 0xdf if @datasette2.sense_low?
        value
      end

      def lines_written
        port_b = @via.port_b_output
        @datasette1.motor = !@pia1.cb2_output
        @datasette2.motor = port_b.nobits?(0x10)
        write_high = port_b.anybits?(0x08)
        @datasette1.write_line = write_high
        @datasette2.write_line = write_high
      end

      private

      def update_running
        running = @datasette1.running? || @datasette2.running?
        return if running == @running

        @running = running
        @running_handler&.call
      end

      # A falling edge on a read line, and the line back up.
      def pulse1
        @pia1.ca1 = false
        @pia1.ca1 = true
      end

      def pulse2
        @via.cb1 = false
        @via.cb1 = true
      end
    end
  end
end
