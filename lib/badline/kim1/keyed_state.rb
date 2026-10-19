# frozen_string_literal: true

module Badline
  class KIM1
    class Bus
      # The RAM, the expansion's too, and the last byte on the bus, in a
      # keyed snapshot module (BL-RAM). The 6530s keep their own 64 bytes.
      module KeyedState
        def save_fields(out)
          @ram.save_fields(out, "ram")
          out.int("data", @data)
        end

        def load_fields(input)
          @ram.load_fields(input, "ram")
          @data = input.byte("data", @data)
        end
      end

      include KeyedState
    end

    class Panel
      # The panel's fields in a keyed snapshot module (BL-PANEL): the
      # TTY/KB jumper, the key held down, the digit lit and its segments
      # since the cycle they lit, the cycles each segment has been lit,
      # and what each digit last showed and when. The teletype restores
      # the line in.
      module KeyedState
        def save_fields(out)
          out.bool("tty", @tty).int("held", @held).int("digit", @digit).int("segments", @segments)
          out.int("since", @since).ints("lit", @lit).ints("shown", @shown).ints("shown_at", @shown_at)
        end

        def load_fields(input)
          @tty = input.bool("tty", false)
          held = input.int("held", -1)
          @held = held.between?(0, KEYS.length - 1) ? held : -1
          digit = input.int("digit", -1)
          @digit = digit.between?(0, DIGITS - 1) ? digit : -1
          @segments = input.masked("segments", 0, 0x7f)
          @since = input.int("since", 0)
          input.ints_into("lit", @lit)
          input.ints_into("shown", @shown)
          input.ints_into("shown_at", @shown_at)
        end
      end

      include KeyedState
    end

    # The machine's own fields in a keyed snapshot module (BL-MACHINE):
    # the family, its setup (Snapshot::KIM1Setup), the cycle count, the
    # SST switch and U3's PB7 wiring, and under host.* whether type_keys
    # is typing, the keys it has still to press, by their place in KEY_NAMES, the one held, when
    # the next goes, and the on_init handlers still to run. The badline
    # version that wrote it is written for reports and never read.
    module KeyedState
      # The keys type_keys presses, as host.pending_keys numbers them.
      KEY_NAMES = (Panel::KEYS + %w[ST RS]).freeze

      # How many more on_init handlers the machine a snapshot was taken of
      # had yet to run than this one has. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      # Whether a snapshot saves now (Machine::Settling): the CPU between
      # instructions or jammed.
      def settled_for_snapshot? = @cpu.boundary? || @cpu.jammed?

      # Nothing on the board defers its work.
      def settle_chips_for_snapshot = nil

      def save_machine_fields(out)
        out.text("family", "kim1").text("written_by", VERSION)
        Snapshot::KIM1Setup.of(self).write_fields(out)
        out.int("cycles", @cycles).bool("sst", @sst).bool("irq_wired", @irq_wired)
        pending = @pending_keys
        out.bool("host.typing", !pending.nil?)
        out.ints("host.pending_keys", pending.map { |name| KEY_NAMES.index(name) }) if pending
        out.bool("host.key_down", @key_down).int("host.next_key_at", @next_key_at)
        out.int("host.init_pending", @cycles <= @init_threshold ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        @sst = input.bool("sst", false)
        @irq_wired = input.bool("irq_wired", false)
        pending = input.ints("host.pending_keys", []).filter_map { |index| KEY_NAMES[index] if index >= 0 }
        @pending_keys = input.bool("host.typing", false) ? pending : nil
        @key_down = input.bool("host.key_down", false)
        @next_key_at = input.int("host.next_key_at", 0)
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end
    end

    include KeyedState
  end
end
