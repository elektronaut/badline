# frozen_string_literal: true

module Badline
  class Joystick
    DIRECTIONS = { up: 0, down: 1, left: 2, right: 3, fire: 4 }.freeze

    # Kept up to date as switches move, since the CIA samples the fire line
    # every cycle to drive the light pen input.
    attr_reader :port_bits

    def initialize
      @port_bits = 0xff
    end

    def press(direction)
      bit = DIRECTIONS[direction]
      @port_bits &= ~(1 << bit) if bit
    end

    def release(direction)
      bit = DIRECTIONS[direction]
      @port_bits |= 1 << bit if bit
    end
  end
end
