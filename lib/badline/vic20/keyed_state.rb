# frozen_string_literal: true

module Badline
  class Vic20
    # The machine's own fields in a keyed snapshot module (Snapshot::Keyed,
    # BL-MACHINE): the family, its RAM expansion by name, the cycle count,
    # the RESTORE key's NMI, and the host's typing still to feed and on_init
    # handlers still to run under host.*.
    module KeyedState
      # How many more on_init handlers the machine a snapshot was taken of had
      # yet to run than this one has. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      # Whether a snapshot saves now (Machine::Settling): the CPU between
      # instructions or jammed.
      def settled_for_snapshot? = @cpu.boundary? || @cpu.jammed?

      # The sound runs itself up to the cycle as its fields are saved.
      def settle_chips_for_snapshot = nil

      def save_machine_fields(out)
        out.text("family", "vic20").text("written_by", VERSION)
        Snapshot::Vic20Setup.new(ram: @ram_configuration).write_fields(out)
        out.int("cycles", @cycles).bool("nmi_asserted", @nmi_asserted)
        pending = @pending_keys
        out.ints("host.pending_keys", pending) if pending
        out.int("host.init_pending", @cycles <= @init_threshold ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        @nmi_asserted = input.bool("nmi_asserted", @nmi_asserted)
        pending = input.ints("host.pending_keys", [])
        @pending_keys = pending.empty? ? nil : pending.dup
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end

      # The serial bus's lines and the datasette's motor and write line from
      # the VIAs, once they are loaded.
      def machine_restored! = via_written
    end

    include KeyedState
  end
end
