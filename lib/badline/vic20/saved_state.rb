# frozen_string_literal: true

module Badline
  class Vic20
    MARKER = "VIC20"

    # The RAM expansion of the machine a State from #snapshot was taken
    # of, a key of Bus::RAM_CONFIGURATIONS.
    def self.setup(state)
      input = Snapshot::StateReader.new(state)
      input.marker(MARKER)
      input.check_stamp
      SavedState.read_ram(input)
    end

    # A new machine, built as the one a State from #snapshot was taken of,
    # at that state.
    def self.restored(state) = new(ram: setup(state)).apply_state(state)

    # The whole machine's state for a snapshot, as Computer's: the
    # machine's own latches, the bus with its RAM and cartridge ROM, the
    # VIC with its sound, both VIAs, the CPU, the datasette and its tape,
    # the disk device 8 serves through the traps, and a true 1541. The
    # serial lines go back into the bus from the restored VIAs. What the
    # host holds stays out: the keyboard, the joystick, RESTORE, the traps
    # and callbacks, whether the display renders, whether the sound
    # records, and whether the datasette records.
    module SavedState
      RAM_CONFIGURATIONS = Bus::RAM_CONFIGURATIONS.keys.freeze

      def self.read_ram(input)
        RAM_CONFIGURATIONS.fetch(input.int)
      rescue IndexError
        raise Snapshot::FormatError, "the state names a VIC-20 RAM expansion badline doesn't know"
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
      # Raises Snapshot::FormatError for a state of another machine or RAM
      # expansion.
      def restore(state)
        check_ram(Vic20.setup(state))
        Vic20.restored(state)
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
        out.int(RAM_CONFIGURATIONS.index(@ram_configuration))
        out.int(@cycles).boolean(@nmi_asserted).boolean(!@pending_keys.nil?)
        out.ints(@pending_keys) if @pending_keys
        out.int(@cycles <= @init_threshold ? @init_handlers.length : 0)
        @bus.save_state(out)
        @vic.save_state(out)
        @sound.save_state(out)
        @via1.save_state(out)
        @via2.save_state(out)
        @cpu.save_state(out)
        @datasette.save_state(out)
        save_trap_drive(out)
        save_drive1541(out)
        save_drive1581(out)
      end

      def load_state(input)
        input.marker(MARKER)
        input.check_stamp
        check_ram(SavedState.read_ram(input))
        @cycles = input.int
        @nmi_asserted = input.boolean?
        @pending_keys = nil
        @pending_keys = input.ints if input.boolean?
        @init_handlers_lost = [input.int - @init_handlers.length, 0].max
        @bus.load_state(input)
        @vic.load_state(input)
        @sound.load_state(input)
        @via1.load_state(input)
        @via2.load_state(input)
        @cpu.load_state(input)
        via_written
        @datasette.load_state(input)
        load_trap_drive(input)
        load_drive1541(input)
        load_drive1581(input)
      end

      private

      # A true 1541 on the serial bus, with its device number.
      def save_drive1541(out)
        out.boolean(!@drive1541.nil?)
        return unless @drive1541

        out.int(@drive1541.device)
        @drive1541.save_state(out)
      end

      def check_ram(ram)
        return if ram == @ram_configuration

        raise Snapshot::FormatError, "the state is of a VIC-20 with #{ram} RAM, not #{@ram_configuration}"
      end
    end
  end
end
