# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # Saving and restoring the WD1772 for a snapshot: its registers and
      # lines, and the command running, down to the byte it is at.
      module State
        def save_state(out)
          [@now, @due, @phase, @command, @track, @sector, @data, @status, @steps, @count, @after_spin_up, @mode,
           @deadline, @id_at, @found, @index, @crc, @write_id, @size].each { |value| out.int(value) }
          [@type1, @drq, @intrq, @motor_on, @inward, @crc_good, @gate_open, @late,
           @settling].each { |flag| out.boolean(flag) }
          out.ints(@bytes).ints(@syncs.map { |sync| sync ? 1 : 0 })
        end

        def load_state(input)
          load_registers(input)
          load_command(input)
          load_flags(input)
          @bytes = input.ints
          @syncs = input.ints.map { |sync| sync == 1 }
        end

        private

        def load_registers(input)
          @now = input.int
          @due = input.int
          @phase = input.int
          @command = input.int
          @track = input.int
          @sector = input.int
          @data = input.int
          @status = input.int
        end

        def load_command(input)
          @steps = input.int
          @count = input.int
          @after_spin_up = input.int
          @mode = input.int
          @deadline = input.int
          @id_at = input.int
          @found = input.int
          @index = input.int
          @crc = input.int
          @write_id = input.int
          @size = input.int
        end

        def load_flags(input)
          @type1 = input.boolean?
          @drq = input.boolean?
          @intrq = input.boolean?
          @motor_on = input.boolean?
          @inward = input.boolean?
          @crc_good = input.boolean?
          @gate_open = input.boolean?
          @late = input.boolean?
          @settling = input.boolean?
        end
      end
    end
  end
end
