# frozen_string_literal: true

module Badline
  class Plus4
    # The machine's own fields in a keyed snapshot module (Snapshot::Keyed,
    # BL-MACHINE): the family, its setup by name (Snapshot::Plus4Setup), the
    # cycle count, and the host's typing still to feed and on_init handlers
    # still to run under host.*. The badline version that wrote it is
    # written for reports and never read.
    module KeyedState
      # How many more on_init handlers the machine a snapshot was taken of had
      # yet to run than this one has. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      # Whether a snapshot saves now (Machine::Settling): the CPU between
      # instructions or jammed.
      def settled_for_snapshot? = @cpu.boundary? || @cpu.jammed?

      # The sound's voices and the SID card's, run up to this cycle.
      def settle_chips_for_snapshot
        @sound.catch_up!
        @sid_card&.catch_up!
      end

      def save_machine_fields(out)
        out.text("family", "plus4").text("written_by", VERSION)
        Snapshot::Plus4Setup.of(self).write_fields(out)
        out.int("cycles", @cycles)
        pending = @pending_keys
        out.ints("host.pending_keys", pending) if pending
        out.int("host.init_pending", booting? ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        pending = input.ints("host.pending_keys", [])
        @pending_keys = pending.empty? ? nil : pending.dup
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end
    end

    include KeyedState
  end
end
