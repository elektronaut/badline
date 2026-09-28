# frozen_string_literal: true

module Badline
  class VIA
    # Timer 2: a one-shot 16-bit counter that decrements on every φ2 cycle,
    # or on every falling edge of PB6 when ACR bit 5 sets it counting pulses.
    # Only its low byte has a latch.
    #
    # Timed, it follows timer 1's one-shot timing: loaded with N it reads N
    # on the cycle after the write, and sets its flag on the cycle it rolls
    # from 0 to $FFFF. Where timer 1 would reload, it rolls on down without
    # further interrupts until the next load. Counting pulses, the flag sets
    # on the pulse that takes it past zero, the N + 1st: the datasheet's
    # "reaches zero" is the same underflow it means in timed mode.
    #
    # While the shift register clocks off it, the low byte also counts as
    # an 8-bit timer of its own: on each low byte underflow it reloads from
    # the latch on the next cycle, which makes the shift clock's half period
    # N + 2 cycles. The borrow still reaches the high byte.
    #
    # ACR bit 5 reaches the count input a cycle after the write, so the
    # counter takes one more step in the mode it leaves.
    class Timer2
      attr_accessor :counter, :latch_low

      # ACR bit 5, which picks PB6 pulses over φ2.
      attr_writer :count_pulses

      # Whether the low byte underflowed on the last cycle.
      attr_reader :low_underflowed

      def initialize
        @counter = 0xffff
        @latch_low = 0xff
        @hold = false
        @low_reload = false
        @armed = false
        @low_underflowed = false
        @count_pulses = @counting_pulses = false
      end

      # The high counter byte write: load the counter with it and the low
      # latch, arm the interrupt and hold the count for a cycle.
      def load(high)
        @counter = (high << 8) | @latch_low
        @hold = true
        @low_reload = false
        @armed = true
      end

      # One φ2 cycle, with whether the shift register clocks off the low
      # byte. Returns true on the cycle that sets the flag.
      def cycle!(sr_service)
        pulses = @counting_pulses
        @counting_pulses = @count_pulses
        return idle! if pulses || @hold

        @low_underflowed = @counter.nobits?(0xff)
        @hold = @low_reload = sr_service && @low_underflowed
        decrement
      end

      # A falling edge on PB6. Returns true when it sets the flag.
      def pulse! = @counting_pulses && decrement

      # How many cycles the timer can run without setting its flag, taken
      # without the shift register clocking off it: until an armed timer
      # underflows, and forever for one counting pulses or unarmed, which
      # only rolls on. None while a load or a switch of mode is under way.
      def quiet_cycles
        return 0 if @hold || @counting_pulses != @count_pulses
        return FastForward::QUIET if @counting_pulses || !@armed

        @counter
      end

      # Runs +cycles+ cycles at once, as many as quiet_cycles allows. The
      # low byte's underflow is set when the last cycle took it from $00.
      def fast_forward(cycles)
        @low_underflowed = false
        return if @counting_pulses

        @counter = (@counter - cycles) & 0xffff
        @low_underflowed = @counter.allbits?(0xff)
      end

      # What the counter and the low byte's underflow don't hold, for
      # comparing the timer at two points.
      def state = [@latch_low, @armed, @hold, @low_reload, @count_pulses, @counting_pulses]

      private

      # A cycle while counting pulses, or held after a load or a low byte
      # underflow: the counter stands still, but the hold still ends, so
      # none carries over into timed mode.
      def idle!
        @counter = (@counter & 0xff00) | @latch_low if @low_reload
        @hold = @low_reload = @low_underflowed = false
      end

      def decrement
        @counter = (@counter - 1) & 0xffff
        interrupt = @armed && @counter == 0xffff
        @armed = false if interrupt
        interrupt
      end
    end
  end
end
