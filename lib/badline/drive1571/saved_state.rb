# frozen_string_literal: true

module Badline
  class Drive1571
    # The drive's state for a snapshot.
    module SavedState
      # The drive's whole state, as the 1541's (Drive1541#save_state), with
      # the CIA and the WD1770's registers. The clock rate, the side and the
      # fast serial direction follow from VIA 1's port A.
      def save_state(out)
        settle!
        out.marker("DRIVE1571")
        out.int(@phase).int(@cycles).boolean(@mechanism.so_pending)
        @serial_port.save_state(out)
        @via1.save_state(out)
        @via2.save_state(out)
        @cia.save_state(out)
        @fdc.save_state(out)
        @bus.save_state(out)
        @cpu.save_state(out)
        @mechanism.save_state(out)
      end

      def load_state(input)
        settle!
        input.marker("DRIVE1571")
        @phase = input.int
        @cycles = input.int
        @mechanism.so_pending = input.boolean?
        @serial_port.load_state(input)
        @via1.load_state(input)
        @via2.load_state(input)
        @cia.load_state(input)
        @fdc.load_state(input)
        @bus.load_state(input)
        @cpu.load_state(input)
        @mechanism.load_state(input)
        @fast_serial_out = @via1.port_a_output.anybits?(FAST_SERIAL_OUT)
        port_a_written(@via1.port_a_output)
        push_fast_output(@fast_serial_out ? fast_pins : 0)
        forget_orbits
      end
    end
  end
end
