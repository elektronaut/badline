# frozen_string_literal: true

module Badline
  module Chips
    class RIOT
      # The interval timer of the 6532 and the 6530: an 8-bit counter behind
      # a prescaler that divides φ2 by 1, 8, 64 or 1024, and the timer's
      # interrupt flag.
      #
      # A write loads the counter and counts it once on the write's own
      # cycle, so the counter reads one less than written from the cycle
      # after, and counts again every interval from the write. A write of N
      # reads N - 1 until cycle T, 0 until cycle N x T, and $FF with the flag
      # set on cycle N x T: 52 at ÷8 sets the flag on cycle 416. From there
      # the counter counts every cycle, so it tells how long ago the flag
      # set, and each count through 0 sets the flag again. Only a write puts
      # the prescaler back.
      #
      # Reading or writing the counter clears the flag, except for a read on
      # the cycle that sets it. Each access takes A3 as the interrupt enable.
      class Timer
        DIVIDERS = [1, 8, 64, 1024].freeze

        attr_reader :counter, :flag
        attr_accessor :irq_enabled

        def initialize
          @counter = 0
          @divider = 1
          @prescale = 1
          @expired = true
          @flag = false
          @irq_enabled = false
          @fired = false
        end

        def irq? = @flag && @irq_enabled

        # +interval+ is A1-A0, picking ÷1, ÷8, ÷64 or ÷1024.
        def write(value, interval, irq_enabled)
          @irq_enabled = irq_enabled
          @flag = false
          @divider = DIVIDERS[interval]
          @prescale = @divider
          @expired = false
          @counter = value
          count
        end

        def read(irq_enabled)
          @irq_enabled = irq_enabled
          @flag = false unless @fired
          @counter
        end

        def cycle!
          @fired = false
          unless @expired
            @prescale -= 1
            return unless @prescale.zero?

            @prescale = @divider
          end
          count
        end

        private

        def count
          @counter = (@counter - 1) & 0xff
          return unless @counter == 0xff

          @expired = true
          @flag = true
          @fired = true
        end
      end
    end
  end
end
