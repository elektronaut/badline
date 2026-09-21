# frozen_string_literal: true

module Badline
  # CIA 1's control ports and the keyboard matrix that spans them.
  #
  # Port A carries the matrix rows together with joystick 2. Every switch is
  # active low, so the joystick is wired-AND onto the lines *before* the matrix
  # settles: a stick held in a direction selects rows of its own, which is
  # where hardware's phantom keypresses come from.
  class ControlPorts
    attr_reader :keyboard, :joystick2

    def initialize(keyboard:, joystick2:)
      @keyboard = keyboard
      @joystick2 = joystick2
    end

    def read_a(port_a, port_b) = scan(port_a, port_b).first

    def read_b(port_a, port_b) = scan(port_a, port_b).last

    private

    def scan(port_a, port_b)
      keyboard.scan(port_a & joystick2.port_bits, port_b)
    end
  end
end
