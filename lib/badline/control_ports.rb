# frozen_string_literal: true

module Badline
  # CIA 1's control ports and the keyboard matrix that spans them.
  #
  # Port A carries the matrix rows together with joystick 2, port B the matrix
  # columns together with joystick 1. Every switch is active low, so the
  # joysticks are wired-AND onto the lines *before* the matrix settles: a stick
  # held in a direction selects rows and columns of its own, which is where
  # hardware's phantom keypresses come from.
  class ControlPorts
    attr_reader :keyboard, :joystick1, :joystick2

    def initialize(keyboard:, joystick1:, joystick2:)
      @keyboard = keyboard
      @joystick1 = joystick1
      @joystick2 = joystick2
    end

    def read_a(port_a, port_b) = scan(port_a, port_b).first

    def read_b(port_a, port_b) = scan(port_a, port_b).last

    private

    def scan(port_a, port_b)
      keyboard.scan(port_a & joystick2.port_bits, port_b & joystick1.port_bits)
    end
  end
end
