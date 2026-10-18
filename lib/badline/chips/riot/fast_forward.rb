# frozen_string_literal: true

module Badline
  module Chips
    class RIOT
      class Timer
        # Running the timer a stretch of cycles at once, as cycle! would one
        # by one, for a drive sleeping through its idle loops.
        module FastForward
          # quiet_cycles for a timer whose flag can't pull IRQ.
          QUIET = 1 << 40

          # How many cycles the timer can run without pulling IRQ: until the
          # count that sets its flag, and forever with its interrupt off.
          def quiet_cycles
            return QUIET unless @irq_enabled

            cycles_to_flag - 1
          end

          # Runs +cycles+ cycles at once.
          def fast_forward(cycles)
            return if cycles.zero?
            return count_expired(cycles) if @expired

            to_flag = cycles_to_flag
            if cycles < to_flag
              count_down(cycles)
            else
              @counter = 0xff
              @prescale = @divider
              @expired = @flag = @fired = true
              count_expired(cycles - to_flag) if cycles > to_flag
            end
          end

          # What the counter and the flag don't hold, for comparing the
          # timer at two points.
          def state = [@divider, @expired, @irq_enabled]

          private

          # The cycles until the count that sets the flag: the count through
          # 0 at the interval, or the next once expired.
          def cycles_to_flag = @expired ? @counter + 1 : @prescale + (@counter * @divider)

          # Counts at the interval, short of 0.
          def count_down(cycles)
            @fired = false
            if cycles < @prescale
              @prescale -= cycles
            else
              rest = cycles - @prescale
              @counter -= 1 + (rest / @divider)
              @prescale = @divider - (rest % @divider)
            end
          end

          # Counts every cycle, setting the flag at each pass through 0.
          def count_expired(cycles)
            to_wrap = @counter + 1
            @counter = (@counter - cycles) & 0xff
            @fired = cycles >= to_wrap && ((cycles - to_wrap) % 256).zero?
            @flag = true if cycles >= to_wrap
          end
        end

        include FastForward
      end
    end
  end
end
