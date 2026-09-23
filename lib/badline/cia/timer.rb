# frozen_string_literal: true

module Badline
  class CIA
    class Timer
      attr_accessor :counter, :latch
      attr_reader :control, :underflowed

      def initialize(control)
        @control = control
        @counter = @latch = 0xffff
        @pipe = 0
        @load_delay = 0
        @reload = false
        @underflowed = false
        @oneshot_linger = 0
        @toggle = true
        settle
      end

      # The level this timer drives on its port B pin: a square wave that
      # flips on each underflow, or a single high tick when one happens.
      def output?
        control.out_mode? ? @toggle : @underflowed
      end

      def cycle!(feed)
        feed &&= @control.value & 0x01 != 0
        if @settled
          return @counter -= 1 if feed && @counter > 1
        elsif @empty
          enter if feed
          return
        end
        run_tick(feed)
      end

      def run_tick(feed)
        @underflowed = false
        @oneshot_linger -= 1 if @oneshot_linger.positive?
        tick(feed)
        settle
      end

      def write_control(value)
        @toggle = true if value.anybits?(0x01) && !started?
        @oneshot_linger = 2 if control.run_mode? && value.nobits?(0x08)
        control.value = value & ~0x10
        @load_delay = 3 if value.anybits?(0x10)
        settle
      end

      def write_latch_low(value)
        @latch = (@latch & 0xff00) | value
      end

      def write_latch_high(value)
        @latch = (value << 8) | (@latch & 0xff)
        @counter = @latch unless started?
      end

      private

      def started?
        @control.value & 0x01 != 0
      end

      def enter
        @pipe = 0b10
        @empty = false
      end

      # With no load, reload or one-shot linger pending, a full pipe only
      # counts and an empty one only waits to be fed.
      def settle
        quiet = (@load_delay | @oneshot_linger).zero? && !@reload
        @settled = quiet && @pipe == 0b11
        @empty = quiet && @pipe.zero?
      end

      def tick(feed)
        counting = @pipe.anybits?(0b01)
        @pipe = (@pipe >> 1) | (feed ? 0b10 : 0)
        loading = @reload || @load_delay == 1
        @reload = false

        if loading
          reload
        elsif premature_underflow?
          underflow
        elsif counting
          count
        end

        forced_load
      end

      def forced_load
        return unless @load_delay.positive?

        @load_delay -= 1
        @counter = @latch if @load_delay == 1
      end

      # the final pipeline stage, before any pending load lands
      def premature_underflow?
        @counter.zero? && @pipe.anybits?(0b01) && started?
      end

      # A load consumes its tick, so the counter never decrements on it
      def reload
        @counter = @latch
        # A zero latch underflows again on the reload tick while running
        underflow if @counter.zero? && started? && @pipe.anybits?(0b01)
      end

      def count
        @counter -= 1 if @counter.positive?
        underflow if @counter.zero? && @pipe.anybits?(0b01)
      end

      def underflow
        @underflowed = true
        @reload = true
        @counter = @latch
        @toggle = !@toggle
        return unless control.run_mode? || @oneshot_linger.positive?

        control.start = false
        @pipe = 0
      end
    end
  end
end
