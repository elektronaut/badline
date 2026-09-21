# frozen_string_literal: true

module Badline
  class CIA
    class Timer
      attr_accessor :counter, :latch
      attr_reader :control, :underflowed

      def initialize(control)
        @control = control
        @counter = @latch = 0x0
        @pipe = 0
        @load_delay = 0
        @reload = false
        @underflowed = false
        @oneshot_linger = 0
        @toggle = true
      end

      # The level this timer drives on its port B pin: a square wave that
      # flips on each underflow, or a single high tick when one happens.
      def output?
        control.out_mode? ? @toggle : @underflowed
      end

      def cycle!(feed, pulse)
        return @counter -= 1 if feed && pulse && steady?

        if (@pipe | @load_delay | @oneshot_linger).zero? && !@reload
          @pipe = 0b10 if feed && started?
          return
        end
        run_tick(feed, pulse)
      end

      def run_tick(feed, pulse)
        @underflowed = false
        @oneshot_linger -= 1 if @oneshot_linger.positive?
        tick(feed && started?, pulse)
      end

      def write_control(value)
        @toggle = true if value.anybits?(0x01) && !started?
        @oneshot_linger = 2 if control.run_mode? && value.nobits?(0x08)
        control.value = value & ~0x10
        @load_delay = 3 if value.anybits?(0x10)
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
        control.value.anybits?(0x01)
      end

      def steady?
        @counter > 1 && @pipe == 0b11 && !@reload &&
          (@load_delay | @oneshot_linger).zero? && started?
      end

      def tick(feed, pulse)
        counting = @pipe.anybits?(0b01) && pulse
        @pipe = (@pipe >> 1) | (feed ? 0b10 : 0)
        loading = @reload || @load_delay == 1
        @reload = false

        if loading
          reload
        elsif premature_underflow?(pulse)
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
      def premature_underflow?(pulse)
        @counter.zero? && pulse && @pipe.anybits?(0b01) && started?
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
