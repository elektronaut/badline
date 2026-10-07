# frozen_string_literal: true

module Badline
  # The 1530 datasette. Plays a pulse stream into CIA 1's FLAG pin while the
  # motor runs with a key pressed, and reports the keys through the cassette
  # sense line on the $01 port. With RECORD down too, it records the
  # machine's write line onto the tape instead.
  class Datasette
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

    # The keys, the motor, the countdown to the next pulse and the tape:
    # its path, its bytes and how far it has played.
    def save_state(out)
      out.marker("DATASETTE")
      out.boolean(@playing).boolean(@motor).int(@countdown).boolean(!@tape.nil?)
      return unless @tape

      out.string(@tape.path).blob(@tape.bytes).int(@tape.position)
    end

    # The tape goes back in from the bytes the state holds, without its
    # host file, unless the tape in is the same one. The sense and flag
    # handlers don't fire.
    def load_state(input)
      input.marker("DATASETTE")
      @playing = input.boolean?
      @motor = input.boolean?
      @countdown = input.int
      return @tape = nil unless input.boolean?

      path = input.string
      bytes = input.blob
      position = input.int
      @tape = Storage::TAP.new(path, bytes:) unless @tape&.path&.b == path && @tape.bytes == bytes
      @tape.position = position
    end

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
