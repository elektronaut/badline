# frozen_string_literal: true

module Badline
  class VIA
    # Timer 2: a one-shot 16-bit counter that decrements on every φ2 cycle,
    # or on every falling edge of PB6 when ACR bit 5 sets it counting pulses.
    # Only its low byte has a latch.
    #
    # Timed, it follows timer 1's one-shot timing: loaded with N it reads N
    # on the cycle after the write, and sets its flag on the cycle it rolls
    # from 0 to $FFFF. It then rolls on down without further interrupts until
    # the next load. Counting pulses, the flag sets on the pulse that takes
    # it past zero, the N + 1st.
    #
    # While the shift register clocks off it, the low byte also counts as
    # an 8-bit timer of its own: on each low byte underflow it reloads from
    # the latch on the next cycle, which makes the shift clock's half period
    # N + 2 cycles. The borrow still reaches the high byte.
    class Timer2
      attr_accessor :counter, :latch_low

      # Whether the low byte underflowed on the last cycle.
      attr_reader :low_underflowed

      def initialize
        @counter = 0xffff
        @latch_low = 0xff
        @hold = false
        @low_reload = false
        @armed = false
        @low_underflowed = false
      end

      # The high counter byte write: load the counter with it and the low
      # latch, arm the interrupt and hold the count for a cycle.
      def load(high)
        @counter = (high << 8) | @latch_low
        @hold = true
        @low_reload = false
        @armed = true
      end

      # One φ2 cycle in timed mode, with whether the shift register clocks
      # off the low byte. Returns true on the cycle that sets the flag.
      def cycle!(sr_service)
        if @hold
          @counter = (@counter & 0xff00) | @latch_low if @low_reload
          @hold = @low_reload = @low_underflowed = false
          return false
        end
        @low_underflowed = @counter.nobits?(0xff)
        @hold = @low_reload = sr_service && @low_underflowed
        decrement
      end

      # A falling edge on PB6 while counting pulses. Returns true when it
      # sets the flag.
      def pulse!
        @hold = false
        decrement
      end

      private

      def decrement
        @counter = (@counter - 1) & 0xffff
        interrupt = @armed && @counter == 0xffff
        @armed = false if interrupt
        interrupt
      end
    end
  end
end
