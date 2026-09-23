# frozen_string_literal: true

module Badline
  class SID
    # ADSR envelope generator.
    #
    # A 15-bit rate counter divides the 1 MHz clock down to one envelope step
    # per period. Attack steps linearly; decay and release run through a
    # second, level-dependent divider that approximates an exponential
    # curve.
    #
    # Each stage runs a cycle or more behind the one feeding it, after
    # reSID 1.0's single-cycle pipeline: the rate counter resets the cycle
    # after it matches, the envelope counter steps two cycles after that,
    # and a gate edge only switches the rate over on its second cycle.
    class Envelope
      # Rate counter comparison values for each ADSR nibble. The counter
      # takes a cycle to reset, so the period is one cycle longer (2ms to
      # 8s over the attack range).
      PERIODS = [8, 31, 62, 94, 148, 219, 266, 312,
                 391, 976, 1953, 3125, 3906, 11_719, 19_531, 31_250].freeze

      # Envelope levels where the exponential divider changes, and the
      # divider it changes to.
      EXPONENTIAL_PERIODS = { 0xff => 1, 0x5d => 2, 0x36 => 4, 0x1a => 8,
                              0x0e => 16, 0x06 => 30, 0x00 => 1 }.freeze

      attr_reader :state, :counter, :env3

      def initialize
        @attack = @decay = @sustain = @release = 0x0
        @gate = false
        @state = @next_state = :release
        @counter = @env3 = 0x00
        @rate_counter = 0
        @rate_period = PERIODS[0]
        @reset_rate_counter = false
        @exponential_counter = 0
        @exponential_period = 1
        @state_pipeline = @envelope_pipeline = @exponential_pipeline = 0
        @hold_zero = true
      end

      def output = @counter

      # The gate edge switches the state over two cycles. Rising, it runs
      # the decay rate for the first of them. The rate counter is left
      # running, so the first step lands somewhere inside the current
      # period.
      def control=(value)
        gate = value.anybits?(0x01)
        return if gate == @gate

        @gate = gate
        gate ? gate_on : gate_off
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

      # ENV3 reads the counter as it stood at the start of the cycle.
      #
      # Lowering the rate period below the current counter sends it the long
      # way round through 2^15 before the envelope can step, the ADSR delay
      # bug that hard restarts rely on. Counting from 0x7fff wraps to 1.
      def cycle!
        @env3 = @counter
        run_pipeline if pipelined?
        return @reset_rate_counter = true if @rate_counter == @rate_period

        @rate_counter += 1
        @rate_counter = 1 if @rate_counter == 0x8000
      end

      # Runs `cycles` cycles as #cycle! would. Between steps only the rate
      # counter moves, so it jumps from one match to the next and the cycles
      # around each step run whole. Frozen at zero, a period changes
      # nothing, so whole periods are counted off at once.
      def fast_forward(cycles)
        while cycles.positive?
          if pipelined?
            cycle!
            cycles -= 1
            next
          end

          @env3 = @counter
          idle = cycles_to_match
          return advance_rate_counter(cycles) if cycles < idle

          advance_rate_counter(idle)
          cycles = skip_frozen_periods(cycles - idle)
        end
      end

      private

      def land_step
        @envelope_pipeline -= 1
        step if @envelope_pipeline.zero? && !@hold_zero
      end

      def gate_on
        @next_state = :attack
        @state = :decay_sustain
        @rate_period = PERIODS[@decay]
        @state_pipeline = 2
        if @reset_rate_counter || @exponential_pipeline == 2
          @envelope_pipeline = @exponential_period == 1 || @exponential_pipeline == 2 ? 2 : 4
        elsif @exponential_pipeline == 1
          @state_pipeline = 3
        end
      end

      def gate_off
        @next_state = :release
        @state_pipeline = @envelope_pipeline.positive? ? 3 : 2
      end

      def state_change
        @state_pipeline -= 1
        if @next_state == :attack
          enter_attack if @state_pipeline.zero?
        elsif (@state == :attack && @state_pipeline.zero?) ||
              (@state == :decay_sustain && @state_pipeline == 1)
          @state = :release
          @rate_period = PERIODS[@release]
        end
      end

      def enter_attack
        @state = :attack
        @rate_period = PERIODS[@attack]
        @hold_zero = false
      end

      # The first attack step also resets the exponential divider.
      def reset_rate_counter
        @rate_counter = 0
        @reset_rate_counter = false
        if @state == :attack
          @exponential_counter = 0
          @envelope_pipeline = 2
        elsif !@hold_zero && (@exponential_counter += 1) == @exponential_period
          @exponential_pipeline = @exponential_period == 1 ? 1 : 2
        end
      end

      def exponential_step
        @exponential_counter = 0
        return unless @state == :release || (@state == :decay_sustain && @counter != sustain_level)

        @envelope_pipeline = 1
      end

      def pipelined?
        @reset_rate_counter || (@state_pipeline | @envelope_pipeline | @exponential_pipeline) != 0
      end

      def run_pipeline
        state_change if @state_pipeline.positive?
        land_step if @envelope_pipeline.positive?
        if @exponential_pipeline.positive? && (@exponential_pipeline -= 1).zero?
          exponential_step
        elsif @reset_rate_counter
          reset_rate_counter
        end
      end

      # Cycles that only count before the rate counter matches its period.
      def cycles_to_match
        return @rate_period - @rate_counter if @rate_counter <= @rate_period

        0x7fff - @rate_counter + @rate_period
      end

      def advance_rate_counter(cycles)
        @rate_counter += cycles
        @rate_counter -= 0x7fff if @rate_counter > 0x7fff
      end

      # With the counter on its period, a frozen envelope comes back to the
      # same state every period plus one cycles. Otherwise the next cycle
      # starts a step.
      def skip_frozen_periods(cycles)
        cycles %= @rate_period + 1 if @hold_zero && @state != :attack
        return cycles unless cycles.positive?

        cycle!
        cycles - 1
      end

      def step
        if @state == :attack
          attack_step
        else
          @counter = (@counter - 1) & 0xff
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
