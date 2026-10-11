# frozen_string_literal: true

module Badline
  class C128
    # The machine's own fields in a keyed snapshot module (Snapshot::Keyed,
    # BL-MACHINE): the family, its model, SID and mode by name, the cycle
    # count, $D030's clock bits on their way, the NMI glue, the two
    # schedulers' offsets (z80_ahead, the Z80's T-states past when it was
    # due, and chips_ahead), an 8502 reset waiting for the bus, and the
    # host's typing and on_init handlers under host.*. They load after the
    # Z80's own fields, which z80_ahead counts from.
    module KeyedState
      def save_machine_fields(out)
        out.text("family", "c128").text("written_by", VERSION)
        snapshot_setup.write_fields(out)
        out.int("cycles", @cycles).int("clock_bits", @clock_bits).bool("nmi_asserted", @nmi_asserted)
        out.bool("cartridge_nmi", @cartridge_nmi).bool("restore_pulse", @restore_pulse)
        out.int("z80_ahead", @z80.cycles - @z80_due).int("chips_ahead", @chips_ahead)
        out.bool("cpu_reset_pending", @cpu_reset_pending)
        pending = @pending_keys
        out.ints("host.pending_keys", pending) if pending
        out.int("host.init_pending", @cycles <= init_threshold ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        @clock_bits = input.int("clock_bits", @clock_bits)
        @nmi_asserted = input.bool("nmi_asserted", @nmi_asserted)
        @cartridge_nmi = input.bool("cartridge_nmi", @cartridge_nmi)
        @restore_pulse = input.bool("restore_pulse", @restore_pulse)
        @z80_due = @z80.cycles - input.int("z80_ahead", @z80.cycles - @z80_due)
        @chips_ahead = input.int("chips_ahead", @chips_ahead)
        @cpu_reset_pending = input.bool("cpu_reset_pending", @cpu_reset_pending)
        pending = input.ints("host.pending_keys", [])
        @pending_keys = pending.empty? ? nil : pending.dup
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end

      # Which CPU has the bus and whose turn it is, from the MMU and the
      # schedulers' offsets, and the serial bus's lines.
      def machine_restored!
        @z80_running = @bus.z80?
        @z80_turn = @z80_running || @chips_ahead.positive?
        push_serial_lines
        push_fast_serial
      end
    end

    include KeyedState
  end
end
