# frozen_string_literal: true

require "badline/drives/datasette/saved_state"
require "badline/drives/datasette/keyed_state"

module Badline
  module Drives
    # The 1530 datasette. Plays a pulse stream into CIA 1's FLAG pin while the
    # motor runs with a key pressed, and reports the keys through the cassette
    # sense line on the $01 port. With RECORD down too, it records the
    # machine's write line onto the tape instead. Built with +level: true+,
    # it also times the read line's level, for a machine that reads that
    # (#read_high?) rather than the falling edges.
    class Datasette
      include SavedState

      # What inserting a tape raises on a machine without a cassette port.
      class Missing < ArgumentError; end

      attr_reader :tape
      attr_writer :motor

      def initialize(tape = nil, level: false)
        @tape = tape
        @level = level
        @connected = true
        @playing = false
        @recording = false
        @write_high = true
        @since = 0
        @motor = false
        @countdown = 0
        @rise_at = 0
        @flag_handler = nil
        @sense_handler = nil
      end

      # Falling edges on the tape read line.
      def on_flag(&handler)
        @flag_handler = handler
      end

      # The cassette sense line, which the $01 port reads back.
      def on_sense_change(&handler)
        @sense_handler = handler
      end

      # Whether the machine has a datasette at its cassette port. The SX-64
      # has none: its keys stay up and it takes no tape.
      def connected? = @connected

      def disconnect!
        eject
        @connected = false
      end

      def insert(tape)
        raise Missing, "this machine has no datasette" unless @connected

        @tape = tape
        rewind
      end

      def eject
        stop!
        @tape = nil
      end

      def rewind
        @tape&.rewind
        @countdown = 0
        @rise_at = 0
      end

      def play! = press(true)
      def stop! = press(false)

      # Presses RECORD and PLAY together.
      def record!
        return if !@connected || @tape.nil?

        press(true)
        @recording = true
        @since = 0
      end

      def recording? = @recording

      # The machine's tape write line. While the deck records with its motor
      # running, each rising edge ends a pulse on the tape, as long as the
      # time since the edge before, and plays back as a falling edge on the
      # read line.
      def write_line=(high)
        rose = high && !@write_high
        @write_high = high
        return unless rose && @recording && running?

        @tape.record_pulse(@since)
        @since = 0
      end

      # Sets the write line's level without recording an edge, as a
      # snapshot loads it.
      def write_level=(high)
        @write_high = high
      end

      def playing? = @playing

      # Sense reads low while a key is down on the deck.
      def sense_low? = @playing

      def motor? = @motor

      def running? = @playing && @motor && !@tape.nil?

      # The tape read line's level, on a datasette built with +level: true+.
      # Each pulse holds it low for its first half and high for its second,
      # up to the falling edge that ends it. A version 2 tape times each
      # half, and a version 0 or 1 tape's pulse plays as two equal halves.
      # It reads high while the tape isn't playing.
      def read_high?
        return true unless running? && !@recording

        @countdown.positive? && @countdown <= @rise_at
      end

      def cycle!
        return unless running?
        return @since += 1 if @recording

        next_pulse if @countdown.zero?
        return if @countdown.zero?

        @countdown -= 1
        @flag_handler&.call if @countdown.zero?
      end

      def inspect
        "#<#{self.class.name} tape=#{@tape ? @tape.class.name : 'none'} " \
          "playing=#{@playing} motor=#{@motor}>"
      end

      private

      def next_pulse
        return @countdown = @tape.next_pulse.to_i unless @level
        return next_half_waves if @tape.half_waves?

        @countdown = @tape.next_pulse.to_i
        @rise_at = @countdown / 2
      end

      def next_half_waves
        first = @tape.next_half_wave.to_i
        @rise_at = @tape.next_half_wave.to_i
        @countdown = first + @rise_at
      end

      def press(down)
        return if down == @playing || !@connected

        finish_recording unless down
        @playing = down
        @sense_handler&.call
      end

      # Releasing the keys ends a recording, and writes the tape out.
      def finish_recording
        return unless @recording

        @recording = false
        @tape.save
      end
    end
  end
end
