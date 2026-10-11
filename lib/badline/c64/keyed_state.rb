# frozen_string_literal: true

module Badline
  class C64
    # The machine's own fields in a keyed snapshot module (Snapshot::Keyed,
    # BL-MACHINE): the family, its setup by name, the cycle count, the NMI
    # glue, the freezer's write count and the REU's hold on the bus, and the
    # host's typing still to feed and on_init handlers still to run under
    # host.*. The badline version that wrote it is written for reports and
    # never read.
    module KeyedState
      def save_machine_fields(out)
        out.text("family", "c64").text("written_by", VERSION)
        Snapshot::C64Setup.of(address_bus).write_fields(out)
        out.int("cycles", @cycles).bool("nmi_asserted", @nmi_asserted).bool("cartridge_nmi", @cartridge_nmi)
        out.bool("restore_pulse", @restore_pulse).bool("freezing", @freezing).int("freeze_writes", @freeze_writes)
        out.bool("dma", @dma)
        pending = @pending_keys
        out.ints("host.pending_keys", pending) if pending
        out.int("host.init_pending", booting? ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        @nmi_asserted = input.bool("nmi_asserted", @nmi_asserted)
        @cartridge_nmi = input.bool("cartridge_nmi", @cartridge_nmi)
        @restore_pulse = input.bool("restore_pulse", @restore_pulse)
        @freezing = input.bool("freezing", @freezing)
        @freeze_writes = input.int("freeze_writes", @freeze_writes)
        @dma = input.bool("dma", @dma)
        pending = input.ints("host.pending_keys", [])
        @pending_keys = pending.empty? ? nil : pending.dup
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end

      # The REU's IRQ line and the serial bus's lines from CIA 2, once the
      # chips are loaded.
      def machine_restored!
        @reu_irq = @reu.nil? ? false : @reu.irq?
        push_serial_lines
      end
    end

    include KeyedState
  end
end
