# frozen_string_literal: true

module Badline
  class Drive1581
    # The drive's state for a snapshot.
    module SavedState
      # The drive's whole state, as the 1541's (Drive1541#save_state), with
      # the 8520 and the WD1772 in place of the VIAs.
      def save_state(out)
        settle!
        out.marker("DRIVE1581")
        out.int(@phase).int(@cycles).boolean(@atn)
        @serial_port.save_state(out)
        @cia.save_state(out)
        @fdc.save_state(out)
        @bus.save_state(out)
        @cpu.save_state(out)
        @mechanism.save_state(out)
      end

      def load_state(input)
        settle!
        input.marker("DRIVE1581")
        @phase = input.int
        @cycles = input.int
        @atn = input.boolean?
        @serial_port.load_state(input)
        @cia.load_state(input)
        @fdc.load_state(input)
        @bus.load_state(input)
        @cpu.load_state(input)
        @mechanism.load_state(input)
        @fast_serial_out = @cia.port_b_lines.anybits?(FAST_SERIAL_OUT)
        ports_written
        push_fast_output(@fast_serial_out ? fast_pins : 0)
        forget_orbits
      end
    end
  end
end
