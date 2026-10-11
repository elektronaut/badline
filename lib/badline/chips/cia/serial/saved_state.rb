# frozen_string_literal: true

module Badline
  class CIA
    class Serial
      # The shift register's state for a snapshot.
      module SavedState
        def save_state(out)
          out.int(@data).int(@shift).int(@steps).optional_int(@empty_in).optional_int(@busy_in)
          out.boolean(@busy).boolean(@abandoned).optional_int(@pending).boolean(@underflow_high).boolean(@in_flight)
          out.int(@flight_up).int(@flight_down).boolean(@idle)
          [@cnt, @cnt_in, @sp_in, @sp_out].each { |level| out.boolean(level) }
        end

        def load_state(input)
          @data = input.int
          @shift = input.int
          @steps = input.int
          @empty_in = input.optional_int
          @busy_in = input.optional_int
          @busy = input.boolean?
          @abandoned = input.boolean?
          @pending = input.optional_int
          load_lines(input)
        end

        private

        def load_lines(input)
          @underflow_high = input.boolean?
          @in_flight = input.boolean?
          @flight_up = input.int
          @flight_down = input.int
          @idle = input.boolean?
          @cnt = input.boolean?
          @cnt_in = input.boolean?
          @sp_in = input.boolean?
          @sp_out = input.boolean?
        end
      end
    end
  end
end
