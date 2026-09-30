# frozen_string_literal: true

module Badline
  class Drive1541
    # Saving and restoring the Mechanism for a snapshot.
    module MechanismState
      # The disk (Disk#save_state) and everything the head, the motor, the
      # stepper and the read and write electronics hold, down to the cell
      # under the head and the read clock's phase.
      def save_state(out)
        out.boolean(!@disk.nil?)
        @disk&.save_state(out)
        [@half_track, @slip, @zone, @clock, @time, @clock_at, @clocks, @shift, @ones, @bits, @write_shift,
         @index, @mask, @cell_end, @width, @next].each { |value| out.int(value) }
        [@motor, @led, @sync, @byte_ready, @writing, @write_gate, @protected, @track_written].each do |flag|
          out.boolean(flag)
        end
        out.optional_int(@write_index)
      end

      # Puts the state back, reusing the disk in when it's the one the state
      # names (Disk::State.load). A disk taken out is flushed, as insert
      # does.
      def load_state(input)
        disk = input.boolean? ? Disk::State.load(input, @disk) : nil
        flush unless disk.equal?(@disk)
        @disk = disk
        load_head(input)
        load_flags(input)
        @write_index = input.optional_int
        head_on_track
      end

      private

      def load_head(input)
        @half_track = input.int
        @slip = input.int
        @zone = input.int
        @clock = input.int
        @time = input.int
        @clock_at = input.int
        @clocks = input.int
        @shift = input.int
        @ones = input.int
        @bits = input.int
        @write_shift = input.int
        @index = input.int
        @mask = input.int
        @cell_end = input.int
        @width = input.int
        @next = input.int
      end

      def load_flags(input)
        @motor = input.boolean?
        @led = input.boolean?
        @sync = input.boolean?
        @byte_ready = input.boolean?
        @writing = input.boolean?
        @write_gate = input.boolean?
        @protected = input.boolean?
        @track_written = input.boolean?
      end
    end
  end
end
