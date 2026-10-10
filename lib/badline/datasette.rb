# frozen_string_literal: true

require "badline/datasette/saved_state"

module Badline
  # The 1530 datasette. Plays a pulse stream into CIA 1's FLAG pin while the
  # motor runs with a key pressed, and reports the keys through the cassette
  # sense line on the $01 port. With RECORD down too, it records the
  # machine's write line onto the tape instead.
  class Datasette
    include SavedState

    # What inserting a tape raises on a machine without a cassette port.
    class Missing < ArgumentError; end

    attr_reader :tape
    attr_writer :motor

    def initialize(tape = nil)
      @tape = tape
      @connected = true
      @playing = false
      @recording = false
      @write_high = true
      @since = 0
      @motor = false
      @countdown = 0
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

    def playing? = @playing

    # Sense reads low while a key is down on the deck.
    def sense_low? = @playing

    def motor? = @motor

    def running? = @playing && @motor && !@tape.nil?

    def cycle!
      return unless running?
      return @since += 1 if @recording

      @countdown = @tape.next_pulse.to_i if @countdown.zero?
      return if @countdown.zero?

      @countdown -= 1
      @flag_handler&.call if @countdown.zero?
    end

    def inspect
      "#<#{self.class.name} tape=#{@tape ? @tape.class.name : 'none'} " \
        "playing=#{@playing} motor=#{@motor}>"
    end

    private

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
