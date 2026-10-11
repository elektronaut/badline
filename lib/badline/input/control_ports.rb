# frozen_string_literal: true

module Badline
  # CIA 1's control ports and the keyboard matrix that spans them.
  #
  # Port A carries the matrix rows together with joystick 2, port B the matrix
  # columns together with joystick 1. Every switch is active low, so the
  # joysticks are wired-AND onto the lines *before* the matrix settles: a stick
  # held in a direction selects rows and columns of its own, which is where
  # hardware's phantom keypresses come from. Paddles and a 1351 mouse have
  # buttons on those same lines.
  #
  # The ports also carry SID's POTX/POTY lines, which reach them through analog
  # switches closed by CIA 1 PA6 (port 1) and PA7 (port 2). Close both and the
  # pots sit in parallel, so SID charges through the lower of the two
  # resistances; close neither and the lines float high. Reading a pot asks the
  # CIA for the current select lines, since a program sets them and then goes
  # straight to SID without touching the ports again.
  #
  # A matrix may have rows beyond port A's eight. Their select lines come from
  # outside the CIA and are pushed into +extra_rows+, bit 0 for the ninth row
  # upwards, active low like port A; idle, every line is high and none of
  # those rows is selected. They settle with port A's lines as rows 8 and up,
  # so their keys reach port B, but port A reads only its own eight.
  class ControlPorts
    PORT1_POTS = 0x40
    PORT2_POTS = 0x80
    FIRE = 0x10

    attr_reader :keyboard, :joystick1, :joystick2
    attr_accessor :device1, :device2, :port_a_source, :extra_rows

    def initialize(keyboard:, joystick1:, joystick2:)
      @keyboard = keyboard
      @joystick1 = joystick1
      @joystick2 = joystick2
      @device1 = nil
      @device2 = nil
      @port_a_source = nil
      @extra_rows = 0xff
    end

    def read_a(port_a, port_b) = scan(port_a, port_b).first & 0xff

    def read_b(port_a, port_b) = scan(port_a, port_b).last

    # Control port 1 pin 6 is both the port B fire line and the VIC's light
    # pen input, so joystick 1's button and a 1351's left button latch
    # $D013/$D014. The CIA samples this every cycle, so it skips the matrix and
    # asks only what the port's own devices drive.
    def port_b4_high? = port_bits(@joystick1, @device1).anybits?(FIRE)

    def pot_x = selected_devices.map(&:pot_x).min || 0xff

    def pot_y = selected_devices.map(&:pot_y).min || 0xff

    private

    def selected_devices
      lines = @port_a_source&.port_a_lines || 0x00
      devices = []
      devices << @device1 if @device1 && lines.anybits?(PORT1_POTS)
      devices << @device2 if @device2 && lines.anybits?(PORT2_POTS)
      devices
    end

    def scan(port_a, port_b)
      keyboard.scan((port_a & port_bits(@joystick2, @device2)) | (@extra_rows << 8),
                    port_b & port_bits(@joystick1, @device1))
    end

    def port_bits(joystick, device)
      device ? joystick.port_bits & device.port_bits : joystick.port_bits
    end
  end
end
