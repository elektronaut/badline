# frozen_string_literal: true

module Badline
  class C128
    MARKER = "C128"

    # The model and the SID of the machine a State from #snapshot was taken
    # of, the arguments C128.new takes.
    def self.setup(state)
      input = Snapshot::StateReader.new(state)
      input.marker(MARKER)
      input.check_stamp
      SavedState.read_setup(input)
    end

    # A new machine, built as the one a State from #snapshot was taken of,
    # at that state.
    def self.restored(state)
      setup = setup(state)
      new(model: setup[0], sid_model: setup[1]).apply_state(state)
    end

    # The whole machine's state for a snapshot, as Computer's: the
    # machine's own latches, the bus with its RAM, the MMU, the chips and
    # the VDC, the CPU, the cartridge, the disk device 8 serves through the
    # traps and a true 1541. The serial lines go back into the bus from the
    # restored CIA 2. What the host holds stays out: the keyboard, the
    # joysticks, CAPS LOCK and 40/80 DISPLAY, the traps and callbacks, and
    # which chip renders.
    module SavedState
      SID_MODELS = %i[mos6581 mos8580].freeze

      # The model's name and the SID's model.
      def self.read_setup(input)
        name = input.string
        known = Model::ALL.any? { |model| model.name == name }
        raise Snapshot::FormatError, "the state names a C128 model badline doesn't know" unless known

        [name, SID_MODELS.fetch(input.int)]
      rescue IndexError
        raise Snapshot::FormatError, "the state names a SID badline doesn't know"
      end

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
        out.marker(MARKER).stamp
        out.string(@model.name).int(SID_MODELS.index(@sid.model))
        out.int(@cycles).boolean(@nmi_asserted).boolean(@cartridge_nmi).boolean(@restore_pulse)
        out.boolean(!@pending_keys.nil?)
        out.ints(@pending_keys) if @pending_keys
        out.int(@cycles <= init_threshold ? @init_handlers.length : 0)
        save_cartridge(out)
        @bus.save_state(out)
        @cpu.save_state(out)
        save_trap_drive(out)
        save_serial_bus(out)
      end

      def load_state(input)
        input.marker(MARKER)
        input.check_stamp
        check_setup(SavedState.read_setup(input))
        @cycles = input.int
        @nmi_asserted = input.boolean?
        @cartridge_nmi = input.boolean?
        @restore_pulse = input.boolean?
        @pending_keys = nil
        @pending_keys = input.ints if input.boolean?
        @init_handlers_lost = [input.int - @init_handlers.length, 0].max
        load_cartridge(input)
        @bus.load_state(input)
        push_serial_lines
        @cpu.load_state(input)
        load_trap_drive(input)
        load_serial_bus(input)
      end

      private

      def check_setup(setup)
        ours = [@model.name, @sid.model]
        return if setup == ours

        raise Snapshot::FormatError, "the state is of a #{setup.join(' with a ')}, not a #{ours.join(' with a ')}"
      end
    end

    include SavedState
  end
end
