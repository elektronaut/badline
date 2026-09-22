# frozen_string_literal: true

module Badline
  class SID
    # ADSR envelope generator.
    #
    # A 15-bit rate counter divides the 1 MHz clock down to one envelope step
    # per period. Attack steps linearly; decay and release run through a
    # second, level-dependent divider that approximates an exponential
    # curve.
    class Envelope
      # Rate counter periods for each ADSR nibble, in cycles at 1 MHz
      # (2ms to 8s over the attack range).
      PERIODS = [9, 32, 63, 95, 149, 220, 267, 313,
                 392, 977, 1954, 3126, 3907, 11_720, 19_532, 31_251].freeze

      # Envelope levels where the exponential divider changes, and the
      # divider it changes to.
      EXPONENTIAL_PERIODS = { 0xff => 1, 0x5d => 2, 0x36 => 4, 0x1a => 8,
                              0x0e => 16, 0x06 => 30, 0x00 => 1 }.freeze

      attr_reader :state, :counter

      def initialize
        @attack = @decay = @sustain = @release = 0x0
        @gate = false
        @state = :release
        @counter = 0x00
        @rate_counter = 0
        @rate_period = PERIODS[0]
        @exponential_counter = 0
        @exponential_period = 1
        @hold_zero = true
      end

      def output = @counter

      # The gate edge picks the new state; the rate counter is left running,
      # so the first step lands somewhere inside the current period.
      def control=(value)
        gate = value.anybits?(0x01)
        if gate && !@gate
          @state = :attack
          @rate_period = PERIODS[@attack]
          @hold_zero = false
        elsif @gate && !gate
          @state = :release
          @rate_period = PERIODS[@release]
        end
        @gate = gate
      end

      def attack_decay=(value)
        @attack = (value >> 4) & 0x0f
        @decay = value & 0x0f
        @rate_period = PERIODS[@attack] if @state == :attack
        @rate_period = PERIODS[@decay] if @state == :decay_sustain
      end

      def sustain_release=(value)
        @sustain = (value >> 4) & 0x0f
        @release = value & 0x0f
        @rate_period = PERIODS[@release] if @state == :release
      end

      def cycle!
        tick_rate_counter
        return unless @rate_counter == @rate_period

        @rate_counter = 0
        step if @state == :attack || (@exponential_counter += 1) == @exponential_period
      end

      # Runs `cycles` cycles as #cycle! would, jumping the rate counter from
      # one period to the next. Frozen at zero, a step changes nothing but
      # the exponential divider, so whole periods are counted off at once.
      def fast_forward(cycles)
        while cycles.positive?
          due = cycles_to_period
          return advance_rate_counter(cycles) if cycles < due

          cycles -= due
          @rate_counter = 0
          step if @state == :attack || (@exponential_counter += 1) == @exponential_period
          return skip_frozen_periods(cycles) if @hold_zero
        end
      end

      private

      # Counting from 0x7fff wraps to 1, not 0 (see #tick_rate_counter).
      def cycles_to_period
        return @rate_period - @rate_counter if @rate_counter < @rate_period

        0x7fff - @rate_counter + @rate_period
      end

      def advance_rate_counter(cycles)
        @rate_counter += cycles
        @rate_counter -= 0x7fff if @rate_counter > 0x7fff
      end

      def skip_frozen_periods(cycles)
        periods = cycles / @rate_period
        @rate_counter = cycles % @rate_period
        @exponential_counter = (@exponential_counter + periods) % @exponential_period
      end

      # Lowering the rate period below the current counter sends it the long
      # way round through 2^15 before the envelope can step, the ADSR delay
      # bug that hard restarts rely on.
      def tick_rate_counter
        @rate_counter += 1
        return unless @rate_counter.anybits?(0x8000)

        @rate_counter = (@rate_counter + 1) & 0x7fff
      end

      # The first attack step also resets the exponential divider.
      def step
        @exponential_counter = 0
        return if @hold_zero

        case @state
        when :attack then attack_step
        when :decay_sustain then @counter -= 1 if @counter != sustain_level
        when :release then @counter = (@counter - 1) & 0xff
        end
        set_exponential_period
      end

      def attack_step
        @counter = (@counter + 1) & 0xff
        return unless @counter == 0xff

        @state = :decay_sustain
        @rate_period = PERIODS[@decay]
      end

      def sustain_level = (@sustain << 4) | @sustain

      # Reaching zero freezes the envelope until the gate is raised again.
      def set_exponential_period
        period = EXPONENTIAL_PERIODS[@counter]
        return unless period

        @exponential_period = period
        @hold_zero = true if @counter.zero?
      end
    end
  end
end
