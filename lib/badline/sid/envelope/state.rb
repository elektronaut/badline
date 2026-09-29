# frozen_string_literal: true

module Badline
  class SID
    class Envelope
      # A snapshot of an envelope: its rates, the gate, the state and the
      # counters and pipelines between them, and the same fields as reSID
      # keeps them, for VICE's SIDEXTENDED module.
      module State
        # The fields reSID keeps for an envelope between cycles: the rate and
        # exponential counters, the level, the state as an index into STATES,
        # whether it holds at zero, the two periods and the pipeline.
        def resid_fields
          [@rate_counter, @exponential_counter, @counter, STATES.index(@state).to_i, @hold_zero ? 1 : 0,
           @rate_period, @exponential_period, @envelope_pipeline]
        end

        # Takes the fields resid_fields gives from `fields`, from `at` on.
        def restore_resid_fields(fields, at)
          @rate_counter = fields[at]
          @exponential_counter = fields[at + 1]
          @counter = @env3 = fields[at + 2]
          state = fields[at + 3]
          @state = @next_state = STATES.fetch(state.clamp(0, STATES.length - 1)).to_sym
          @hold_zero = fields[at + 4] != 0
          @rate_period = fields[at + 5]
          @exponential_period = fields[at + 6]
          @envelope_pipeline = fields[at + 7]
        end

        def save_state(out)
          [@attack, @decay, @sustain, @release].each { |rate| out.int(rate) }
          out.boolean(@gate).int(STATES.index(@state)).int(STATES.index(@next_state))
          out.int(@counter).int(@env3).int(@rate_counter).int(@rate_period).boolean(@reset_rate_counter)
          out.int(@exponential_counter).int(@exponential_period)
          out.int(@state_pipeline).int(@envelope_pipeline).int(@exponential_pipeline).boolean(@hold_zero)
        end

        def load_state(input)
          @attack = input.int
          @decay = input.int
          @sustain = input.int
          @release = input.int
          @gate = input.boolean?
          @state = STATES.fetch(input.int).to_sym
          @next_state = STATES.fetch(input.int).to_sym
          load_counters(input)
        end

        private

        def load_counters(input)
          @counter = input.int
          @env3 = input.int
          @rate_counter = input.int
          @rate_period = input.int
          @reset_rate_counter = input.boolean?
          @exponential_counter = input.int
          @exponential_period = input.int
          @state_pipeline = input.int
          @envelope_pipeline = input.int
          @exponential_pipeline = input.int
          @hold_zero = input.boolean?
        end
      end
    end
  end
end
