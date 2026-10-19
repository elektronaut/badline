# frozen_string_literal: true

module Badline
  class KIM1
    # The cassette deck on U2's PB7 (User Manual, appendix E). Playing, it
    # drives PB7 as the board's PLL and comparator would from the tape
    # (Storage::KIMTape#edges), which the monitor's LOADT ($1873) reads.
    # Recording, it puts each change of PB7, which DUMPT ($1800) toggles as
    # a square wave, on the tape as a crossing, in place of whatever was
    # on the tape from there on. Stopping a recording writes the tape to
    # its file.
    #
    # Nothing on the board starts or stops the deck: the tape moves while
    # PLAY or RECORD is down, a microsecond, a cycle, at a time.
    class Tape
      attr_reader :tape

      # +clock+ answers +cycles+.
      def initialize(clock)
        @clock = clock
        @tape = Storage::KIMTape.new
        @playing = false
        @recording = false
        @stopped_at = 0
        @started = 0
        @edges = []
        @next_edge = 0
        @high = true
        @output_high = true
      end

      def playing? = @playing

      def recording? = @recording

      # How far into the tape the deck is, in microseconds.
      def position = moving? ? @stopped_at + @clock.cycles - @started : @stopped_at

      # Puts `tape` in the deck, wound back to its start.
      def insert_tape(tape)
        stop
        @tape = tape
        @stopped_at = 0
      end

      # Takes the tape out, leaving a blank one with no file.
      def eject
        insert_tape(Storage::KIMTape.new)
      end

      def rewind
        stop
        @stopped_at = 0
      end

      # Presses PLAY.
      def play
        stop
        @edges = @tape.edges
        at = @stopped_at
        index = 0
        index += 1 while index < @edges.length && @edges[index] <= at
        @next_edge = index
        @high = index.even?
        start
        @playing = true
      end

      # Presses RECORD and PLAY.
      def record
        stop
        @tape.erase_from(@stopped_at)
        start
        @recording = true
      end

      def stop
        finish_recording = @recording
        @stopped_at = position
        @playing = @recording = false
        @tape.save if finish_recording && !@tape.path.empty?
      end

      # PB7 as the deck drives it, in bit 7 of a port B read: the
      # comparator's level while the tape plays, and high otherwise.
      def input
        return 0xff unless @playing

        at = position
        edges = @edges
        while @next_edge < edges.length && edges[@next_edge] <= at
          @high = !@high
          @next_edge += 1
        end
        @high ? 0xff : 0x7f
      end

      # U2's port B after a write to it, which records a change of PB7.
      def output(port_b)
        high = port_b.anybits?(0x80)
        return if high == @output_high

        @output_high = high
        @tape.record(position) if @recording
      end

      private

      def moving? = @playing || @recording

      def start
        @started = @clock.cycles
      end
    end
  end
end
