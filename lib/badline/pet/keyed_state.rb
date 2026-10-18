# frozen_string_literal: true

module Badline
  class PET
    # The machine's own fields in a keyed snapshot module (Snapshot::Keyed,
    # BL-MACHINE): the family, its setup by name (Snapshot::PETSetup), the
    # cycle count, the vertical drive line, and the host's typing still to
    # feed and on_init handlers still to run under host.*. The badline
    # version that wrote it is written for reports and never read.
    module KeyedState
      # How many more on_init handlers the machine a snapshot was taken of had
      # yet to run than this one has. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      # Whether a snapshot saves now (Machine::Settling): the CPU between
      # instructions or jammed.
      def settled_for_snapshot? = @cpu.boundary? || @cpu.jammed?

      # Nothing defers its work past the cycle.
      def settle_chips_for_snapshot = nil

      # Settles for a snapshot, then runs on until a 2031's CPU is between
      # instructions with the PET's, as xpet saves both.
      def settle_for_vice!
        ran = settle_for_snapshot!
        drive = @drive2031
        return ran if drive.nil?

        until ran >= Machine::Settling::LIMIT || (drive.cpu.boundary? && settled_for_snapshot?)
          cycle!
          ran += 1
        end
        ran
      end

      def save_machine_fields(out)
        out.text("family", "pet").text("written_by", VERSION)
        Snapshot::PETSetup.of(self).write_fields(out)
        out.int("cycles", @cycles).bool("vertical_drive", @vertical_drive)
        pending = @pending_keys
        out.ints("host.pending_keys", pending) if pending
        out.int("host.init_pending", @cycles <= @init_threshold ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        @vertical_drive = input.bool("vertical_drive", @vertical_drive)
        pending = input.ints("host.pending_keys", [])
        @pending_keys = pending.empty? ? nil : pending.dup
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end
    end

    include KeyedState
  end
end
