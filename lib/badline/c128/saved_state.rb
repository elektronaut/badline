# frozen_string_literal: true

require "badline/snapshot/c128_setup"

module Badline
  class C128
    # How the machine a State from #snapshot was taken of was built.
    def self.setup(state) = Snapshot::C128Setup.from(state)

    # A new machine, built as the one a State from #snapshot was taken of,
    # at that state.
    def self.restored(state) = setup(state).build.apply_state(state)

    # The whole machine's state for a snapshot, as Computer's: the
    # machine's own latches, FAST and TEST as they last took hold, the bus with its RAM, the MMU, the chips and
    # the VDC, the CPU, the cartridge, the disk device 8 serves through the
    # traps and a true 1541. The serial lines go back into the bus from the
    # restored CIA 2. What the host holds stays out: the keyboard, the
    # joysticks, CAPS LOCK and 40/80 DISPLAY, the traps and callbacks, and
    # which chip renders.
    module SavedState
      # How many more on_init handlers the machine a State was taken of had
      # yet to run than this one has. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      def snapshot
        out = Snapshot::StateWriter.new
        save_state(out)
        out.state
      end

      # Takes the machine back to a State from #snapshot, trying it on a new
      # machine first, so one that fails leaves this machine as it was.
      # Raises Snapshot::FormatError for a state of another model or SID.
      def restore(state)
        check_setup(C128.setup(state))
        C128.restored(state)
        apply_state(state)
      end

      # Puts a State into the machine without trying it on a new one first.
      def apply_state(state)
        input = Snapshot::StateReader.new(state)
        load_state(input)
        raise Snapshot::FormatError, "the state goes on past the machine" unless input.finished?

        self
      end

      def save_state(out)
        out.marker(Snapshot::C128Setup::MARKER).stamp
        snapshot_setup.write(out)
        out.int(@cycles).int(@clock_bits).boolean(@nmi_asserted).boolean(@cartridge_nmi).boolean(@restore_pulse)
        out.boolean(!@pending_keys.nil?)
        out.ints(@pending_keys) if @pending_keys
        out.int(@cycles <= init_threshold ? @init_handlers.length : 0)
        save_cartridge(out)
        @bus.save_state(out)
        @cpu.save_state(out)
        @z80.save_state(out)
        out.int(@z80_due).int(@chips_ahead).boolean(@cpu_reset_pending)
        save_trap_dos(out)
        save_serial_bus(out)
      end

      def load_state(input)
        input.marker(Snapshot::C128Setup::MARKER)
        input.check_stamp
        check_setup(Snapshot::C128Setup.read(input))
        @cycles = input.int
        @clock_bits = input.int
        @nmi_asserted = input.boolean?
        @cartridge_nmi = input.boolean?
        @restore_pulse = input.boolean?
        @pending_keys = nil
        @pending_keys = input.ints if input.boolean?
        @init_handlers_lost = [input.int - @init_handlers.length, 0].max
        load_cartridge(input)
        @cpu_reset_pending = false
        @bus.load_state(input)
        push_serial_lines
        @cpu.load_state(input)
        load_z80(input)
        load_trap_dos(input)
        load_serial_bus(input)
        push_fast_serial
      end

      private

      # The Z80 and which CPU has the bus. The bus, restored before it,
      # hands the bus to its CPU without resetting the 8502.
      def load_z80(input)
        @z80_running = @bus.z80?
        @z80.load_state(input)
        @z80_due = input.int
        @chips_ahead = input.int
        @cpu_reset_pending = input.boolean?
        @z80_turn = @z80_running || @chips_ahead.positive?
      end

      # How this machine was built.
      def snapshot_setup
        Snapshot::C128Setup.new(model: @model.name, sid_model: @sid.model, mode: @c64_built ? :c64 : :c128)
      end

      def check_setup(setup)
        ours = snapshot_setup
        return if setup == ours

        raise Snapshot::FormatError, "the state is of a #{setup}, not a #{ours}"
      end
    end

    include SavedState
  end
end
