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

      # Whether the timer is stopped with nothing in its pipeline, so a
      # cycle changes nothing.
      def idle? = @empty && !started?

      # Whether the timer counts ø2 in continuous mode with nothing pending
      # but the reload after an underflow, so fast_forward can run it. A
      # latch below 2 is left out.
      def free_running?
        started? && !@control.run_mode? && @control.value.nobits?(0x20) && @latch >= 2 && @pipe == 0b11 &&
          (@load_delay | @oneshot_linger).zero? && (@settled || @reload)
      end

      # Runs a free-running timer +cycles+ cycles at once, as cycle! would:
      # an underflow every latch + 1 cycles, each one followed by the
      # reload. Returns the underflows.
      def fast_forward(cycles)
        return 0 if cycles.zero?
        return after_underflow(cycles, 0) unless @settled

        if cycles < @counter
          @counter -= cycles
          return 0
        end
        after_underflow(cycles - @counter, 1)
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

      # The counter, the latch and the pipeline between them. The control
      # register is the CIA's to save.
      def save_state(out)
        out.int(@counter).int(@latch).int(@pipe).int(@load_delay).boolean(@reload).boolean(@underflowed)
        out.int(@oneshot_linger).boolean(@toggle).boolean(@settled).boolean(@empty)
      end

      def load_state(input)
        @counter = input.int
        @latch = input.int
        @pipe = input.int
        @load_delay = input.int
        @reload = input.boolean?
        @underflowed = input.boolean?
        @oneshot_linger = input.int
        @toggle = input.boolean?
        @settled = input.boolean?
        @empty = input.boolean?
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

      # Whether the timer's PB output toggle is high, and its count pipeline
      # as two bits, the newer stage high.
      attr_reader :toggle, :pipe

      # Sets the control register without its load strobe, the toggle and
      # the count pipeline, as a VICE snapshot gives them.
      def restore_pipeline(control, toggle, pipe)
        @control.value = control & ~0x10
        @toggle = toggle
        @pipe = pipe
        settle
      end

      private

      def started?
        @control.value & 0x01 != 0
      end

      # Where fast_forward lands +cycles+ after an underflow, with
      # +underflows+ underflows counted so far.
      def after_underflow(cycles, underflows)
        periods, rest = cycles.divmod(@latch + 1)
        underflows += periods
        @toggle = !@toggle if underflows.odd?
        @underflowed = rest.zero?
        @reload = rest.zero?
        @counter = @latch - (rest.zero? ? 0 : rest - 1)
        settle
        underflows
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
