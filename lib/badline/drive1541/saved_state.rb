# frozen_string_literal: true

module Badline
  class Drive1541
    # The drive's state for a snapshot.
    module SavedState
      # The drive's whole state: its clock phase, the CPU, RAM, both VIAs,
      # the serial port's latch of the C64's lines and the mechanism with its
      # disk. The drive settles first, so it is awake and not recording a
      # pass, and a restored drive starts the same way, its orbits forgotten
      # from the state it takes: Idle's and Orbit's bookkeeping
      # isn't stored. The device number, the host's clock rate and whether
      # the drive may sleep are the machine's wiring.
      def save_state(out)
        settle!
        out.marker("DRIVE1541")
        out.int(@phase).int(@cycles).boolean(@mechanism.so_pending)
        @serial_port.save_state(out)
        @via1.save_state(out)
        @via2.save_state(out)
        @bus.save_state(out)
        @cpu.save_state(out)
        @mechanism.save_state(out)
      end

      def load_state(input)
        settle!
        input.marker("DRIVE1541")
        @phase = input.int
        @cycles = input.int
        @mechanism.so_pending = input.boolean?
        @serial_port.load_state(input)
        @via1.load_state(input)
        @via2.load_state(input)
        @bus.load_state(input)
        @cpu.load_state(input)
        @mechanism.load_state(input)
        forget_orbits
      end
    end
  end
end
