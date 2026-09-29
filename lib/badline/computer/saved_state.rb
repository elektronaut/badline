# frozen_string_literal: true

module Badline
  class Computer
    # The whole machine's state for a snapshot: the machine's own latches,
    # the bus and its chips, the CPU, and what is attached to it.
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
      def restore(state)
        input = Snapshot::StateReader.new(state)
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
        out.marker("COMPUTER")
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
      end

      def load_state(input)
        input.marker("COMPUTER")
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
      end

      private

      def check_setup(setup)
        ours = Snapshot::Setup.of(address_bus)
        return if setup == ours

        raise Snapshot::FormatError, "the state is of a machine with #{setup}, not #{ours}"
      end

      def save_cartridge(out)
        cartridge = address_bus.cartridge
        out.boolean(!cartridge.nil?)
        cartridge&.save_setup(out)
      end

      # A cartridge comes back built afresh from the setup it was built
      # with, before the address bus puts its state into it.
      def load_cartridge(input)
        if input.boolean?
          connect_cartridge(Cartridge.from_setup(input))
        elsif address_bus.cartridge
          address_bus.detach_cartridge
        end
      end

      # The disk device 8 serves through the traps, with the traps' own
      # state: open channels, the drive's status and RAM, a SAVE under way.
      def save_trap_drive(out)
        out.boolean(!@drive.nil?)
        return unless @drive

        @drive.save_state(out)
        @serial_trap.save_state(out)
        @save_trap.save_state(out)
      end

      def load_trap_drive(input)
        return unmount unless input.boolean?

        storage = Storage.reopen(input)
        unmount
        mount(storage)
        @drive.load_state(input)
        @serial_trap.load_state(input)
        @save_trap.load_state(input)
      end

      # The serial bus, whose presence decides what CIA 2's port A reads,
      # and a true 1541 on it.
      def save_serial_bus(out)
        out.boolean(!@iec_bus.nil?).boolean(!@drive1541.nil?)
        return unless @drive1541

        out.int(@drive1541.device)
        @drive1541.save_state(out)
      end

      def load_serial_bus(input)
        iec_bus if input.boolean?
        return detach_drive1541 unless input.boolean?

        device = input.int
        detach_drive1541 if @drive1541 && @drive1541.device != device
        attach_drive1541(Drive1541.new(device:)) unless @drive1541
        @drive1541.load_state(input)
      end
    end
  end
end
