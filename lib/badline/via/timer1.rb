# frozen_string_literal: true

module Badline
  class VIA
    # Timer 1: a 16-bit counter that decrements on every φ2 cycle, with a
    # latch it reloads from in free-running mode and the PB7 output.
    #
    # Writing the high counter byte loads the counter on the cycle after,
    # so a timer loaded with N reads N, N-1, ... 0 and then $FFFF, which is
    # the cycle its interrupt flag sets: N + 1.5 cycles after the write in
    # the datasheet's terms. Free running, the counter reloads from the
    # latch on the next cycle, which makes the period N + 2 cycles. In
    # one-shot mode it rolls on down from $FFFF instead, and only the first
    # timeout after the load sets the flag.
    class Timer1
      attr_accessor :counter, :latch

      # The level the timer drives on PB7 when ACR bit 7 hands it the pin.
      attr_reader :pb7

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

      private

      # Free running, PB7 inverts and the flag sets on every timeout. One
      # shot, PB7 goes back high and the flag sets once. Returns whether it
      # sets.
      def timeout(free_run)
        interrupt = free_run || @armed
        @reload = free_run
        @armed &&= free_run
        @pb7 = free_run ? !@pb7 : true
        interrupt
      end
    end
  end
end
