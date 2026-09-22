# frozen_string_literal: true

module Badline
  # The 1530 datasette. Plays a pulse stream into CIA 1's FLAG pin while the
  # motor runs with a key pressed, and reports the keys through the cassette
  # sense line on the $01 port.
  class Datasette
    attr_reader :tape
    attr_writer :motor

    def initialize(tape = nil)
      @tape = tape
      @playing = false
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

    def insert(tape)
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

    def playing? = @playing

    # Sense reads low while a key is down on the deck.
    def sense_low? = @playing

    def motor? = @motor

    def running? = @playing && @motor && !@tape.nil?

    def cycle!
      return unless running?

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
      return if down == @playing

      @playing = down
      @sense_handler&.call
    end
  end
end
