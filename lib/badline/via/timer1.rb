# frozen_string_literal: true

module Badline
  class VIA
    # Timer 1: a 16-bit counter that decrements on every φ2 cycle, with a
    # latch it reloads from on every timeout and the PB7 output.
    #
    # Writing the high counter byte loads the counter on the cycle after,
    # so a timer loaded with N reads N, N-1, ... 0 and then $FFFF, which is
    # the cycle its interrupt flag sets: N + 1.5 cycles after the write in
    # the datasheet's terms. The counter then reloads from the latch on the
    # next cycle, which makes the period N + 2 cycles. It does so in one-shot
    # mode too, unlike timer 2.
    #
    # Only a write of the high counter byte arms the timer. An armed timeout
    # sets the flag and inverts PB7, and in one-shot mode disarms it, so the
    # first timeout after the load alone does. Free-running keeps it armed,
    # but switching to free-running doesn't arm it: an unarmed timer counts
    # and reloads without touching the flag or PB7. The load pulls PB7 low,
    # and ACR bit 7 turning on drives it high, so a timer loaded before its
    # PB7 output is enabled reads high until the timeout pulls it low.
    class Timer1
      attr_accessor :counter, :latch

      # The level the timer drives on PB7 when ACR bit 7 hands it the pin.
      attr_reader :pb7

      # ACR bit 7 turning on hands PB7 to the timer high.
      def pb7_enabled!
        @pb7 = true
      end

      def initialize
        @counter = @latch = 0xffff
        @reload = @hold = false
        @armed = false
        @pb7 = true
      end

      def write_latch_low(value)
        @latch = (@latch & 0xff00) | value
      end

      def write_latch_high(value)
        @latch = (value << 8) | (@latch & 0xff)
      end

      # The high counter byte write: load from the latch, hold the count
      # for a cycle, arm the interrupt and pull PB7 low.
      def start!
        @counter = @latch
        @hold = true
        @reload = false
        @armed = true
        @pb7 = false
      end

      # One φ2 cycle. Returns true on the cycle that sets the interrupt flag.
      def cycle!(free_run)
        if @hold || @reload
          @counter = @latch if @reload
          @hold = @reload = false
          return false
        end
        @counter = (@counter - 1) & 0xffff
        @counter == 0xffff && timeout(free_run)
      end

      # How many cycles the timer can run without setting its flag: until
      # an armed timer's timeout, and forever for an unarmed one, whose
      # timeouts only reload the counter. None while an armed timer loads
      # or reloads.
      def quiet_cycles
        return FastForward::QUIET unless @armed
        return 0 if @hold || @reload

        @counter
      end

      # Runs +cycles+ cycles at once, as many as quiet_cycles allows. An
      # unarmed timer goes round its period of latch + 2 cycles: the
      # timeout at $FFFF, the reload, and latch down to 0.
      def fast_forward(cycles)
        if @hold || @reload
          cycle!(false)
          cycles -= 1
        end
        return @counter -= cycles if cycles <= @counter

        phase = (cycles - @counter - 1) % (@latch + 2)
        @reload = phase.zero?
        @counter = @reload ? 0xffff : @latch - phase + 1
      end

      def save_state(out)
        out.int(@counter).int(@latch).boolean(@hold).boolean(@reload).boolean(@armed).boolean(@pb7)
      end

      def load_state(input)
        @counter = input.int
        @latch = input.int
        @hold = input.boolean?
        @reload = input.boolean?
        @armed = input.boolean?
        @pb7 = input.boolean?
      end

      # What the counter and PB7 don't hold, for comparing the timer at two
      # points.
      def state = [@latch, @armed]

      private

      # The counter reloads either way. Armed, PB7 inverts and the flag
      # sets, and one-shot mode disarms. Returns whether the flag sets.
      def timeout(free_run)
        interrupt = @armed
        @reload = true
        @pb7 = !@pb7 if @armed
        @armed &&= free_run
        interrupt
      end
    end
  end
end
