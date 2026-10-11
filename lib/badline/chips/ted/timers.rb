# frozen_string_literal: true

module Badline
  module Chips
    class TED
      # The three 16-bit timers at $FF00-$FF05, which count down once a
      # single clock cycle whatever clock the CPU runs at. Each raises its
      # interrupt flag as it counts down to zero. Timer 1's next count then
      # loads the value last written to it, and timers 2 and 3 roll over to
      # $FFFF.
      #
      # A write to a timer's low byte stops it until its high byte is
      # written. Timer 1's writes set its reload value and its count
      # together, and timers 2 and 3's set the count.
      module Timers
        # The interrupt flag each timer raises in $FF09.
        TIMER_FLAGS = [0x08, 0x10, 0x40].freeze

        # The counts, the reload value of timer 1, and which timers run.
        attr_reader :timer_counts, :timer_running

        private

        def reset_timers
          @timer_counts = [0, 0, 0]
          @timer_running = [false, false, false]
          @timer1_reload = 0
        end

        def count_timers
          i = 0
          while i < 3
            count_timer(i) if @timer_running[i]
            i += 1
          end
        end

        def count_timer(index)
          count = @timer_counts[index]
          if count.zero? && index.zero?
            @timer_counts[0] = @timer1_reload
            return
          end

          count = (count - 1) & 0xffff
          @timer_counts[index] = count
          @interrupt_flags |= TIMER_FLAGS[index] if count.zero?
        end

        def read_timer(register)
          count = @timer_counts[register >> 1]
          register.even? ? count & 0xff : count >> 8
        end

        def write_timer(register, value)
          index = register >> 1
          count = @timer_counts[index]
          count = register.even? ? (count & 0xff00) | value : (count & 0x00ff) | (value << 8)
          @timer_counts[index] = count
          @timer1_reload = count if index.zero?
          @timer_running[index] = register.odd?
        end
      end
    end
  end
end
