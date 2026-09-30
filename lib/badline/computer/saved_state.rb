# frozen_string_literal: true

module Badline
  class Computer
    # The keyword arguments Computer.new takes to build the machine a
    # State from #snapshot was taken of.
    def self.setup(state)
      input = Snapshot::StateReader.new(state)
      input.marker("COMPUTER")
      input.check_stamp
      Snapshot::Setup.read(input)
    end

    # A new machine, built as the one a State from #snapshot was taken of,
    # at that state. `detached` builds it without the host's files
    # (Snapshot::StateReader).
    def self.restored(state, detached: false) = setup(state).build.apply_state(state, detached:)

    # The whole machine's state for a snapshot: the machine's own latches,
    # the bus and its chips, the CPU, and what is attached to it
    # (Attachments).
    module SavedState
      # How many more on_init handlers the machine a State was taken of had
      # yet to run than this one has: they are the host's blocks, which a
      # State can't hold. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      # The machine's whole state, in memory. #restore takes the machine, or
      # another built with the same chip models, region and RAM expansion,
      # back to it. The cartridge, the disk in device 8, a true 1541 and its
      # disk and the tape go in the state too. What the host holds stays
      # out: the keyboard, the joysticks and the pot devices, the traps and
      # callbacks, whether the display renders and whether the SID records.
      def snapshot
        out = Snapshot::StateWriter.new
        save_state(out)
        out.state
      end

      # Takes the machine back to a State from #snapshot. The machine keeps
      # its chips, its traps and its callbacks, and puts in the cartridge,
      # drives and tape the state has, taking out any it hasn't. Raises
      # Snapshot::FormatError for a state of a machine built another way.
      # The state goes into a new machine first, so one that fails leaves
      # this machine as it was.
      def restore(state)
        check_setup(Computer.setup(state))
        Computer.restored(state)
        apply_state(state)
      end

      # Puts a State into the machine without trying it on a new one
      # first, for a machine built for it (Computer.restored): a state that
      # fails leaves the machine part restored. `detached` restores it
      # without the host's files (Snapshot::StateReader).
      def apply_state(state, detached: false)
        input = Snapshot::StateReader.new(state, detached:)
        load_state(input)
        raise Snapshot::FormatError, "the state goes on past the machine" unless input.finished?

        self
      end

      # Sets the machine's cycle count, for a snapshot from VICE, which
      # counts from its own clock.
      def resume_at(cycles)
        @cycles = cycles
      end

      def save_state(out)
        out.marker("COMPUTER").stamp
        Snapshot::Setup.of(address_bus).write(out)
        out.int(@cycles).boolean(@nmi_asserted).boolean(@cartridge_nmi).boolean(@restore_pulse).boolean(@freezing)
        out.int(@freeze_writes).boolean(!@pending_keys.nil?)
        out.ints(@pending_keys) if @pending_keys
        out.int(booting? ? @init_handlers.length : 0)
        save_cartridge(out)
        address_bus.save_state(out)
        @cpu.save_state(out)
        save_trap_drive(out)
        save_serial_bus(out)
        save_reu(out)
      end

      def load_state(input)
        input.marker("COMPUTER")
        input.check_stamp
        check_setup(Snapshot::Setup.read(input))
        @cycles = input.int
        @nmi_asserted = input.boolean?
        @cartridge_nmi = input.boolean?
        @restore_pulse = input.boolean?
        @freezing = input.boolean?
        @freeze_writes = input.int
        @pending_keys = nil
        @pending_keys = input.ints if input.boolean?
        @init_handlers_lost = [input.int - @init_handlers.length, 0].max
        load_cartridge(input)
        address_bus.load_state(input)
        @cpu.load_state(input)
        load_trap_drive(input)
        load_serial_bus(input)
        load_reu(input)
      end

      private

      def check_setup(setup)
        ours = Snapshot::Setup.of(address_bus)
        return if setup == ours

        raise Snapshot::FormatError, "the state is of a machine with #{setup}, not #{ours}"
      end
    end
  end
end
