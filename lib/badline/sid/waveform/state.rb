# frozen_string_literal: true

module Badline
  class SID
    class Waveform
      # A snapshot of an oscillator: its phase, the noise register and the
      # output latch, and the same fields as reSID keeps them, for VICE's
      # SIDEXTENDED module. The model's tables and the voices it syncs with
      # are the SID's wiring.
      module State
        # The fields reSID keeps for an oscillator between cycles: the phase,
        # the noise register, its shift pipeline and reset countdown, the
        # floating output's countdown and the pulse level.
        def resid_fields
          [@accumulator, @shift_register, @shift_pipeline, @shift_register_reset, @floating_ttl, @pulse]
        end

        # Takes the fields resid_fields gives from `fields`, from `at` on.
        def restore_resid_fields(fields, at)
          @accumulator = fields[at]
          @shift_register = fields[at + 1]
          @shift_pipeline = fields[at + 2]
          @shift_register_reset = fields[at + 3]
          @floating_ttl = fields[at + 4]
          @pulse = fields[at + 5]
          @stale = true
        end

        def save_state(out)
          out.int(@accumulator).int(@delayed_triangle).int(@delayed_sawtooth)
          out.int(@shift_register).int(@shift_register_reset).int(@shift_pipeline)
          out.int(@frequency).int(@pulse_width).int(@selected)
          [@test, @ring, @sync, @msb_rising].each { |flag| out.boolean(flag) }
          out.int(@floating).int(@floating_ttl).int(@pulse).int(@output).boolean(@stale)
        end

        def load_state(input)
          @accumulator = input.int
          @delayed_triangle = input.int
          @delayed_sawtooth = input.int
          @shift_register = input.int
          @shift_register_reset = input.int
          @shift_pipeline = input.int
          @frequency = input.int
          @pulse_width = input.int
          @selected = input.int
          load_latches(input)
        end

        private

        def load_latches(input)
          @test = input.boolean?
          @ring = input.boolean?
          @sync = input.boolean?
          @msb_rising = input.boolean?
          @floating = input.int
          @floating_ttl = input.int
          @pulse = input.int
          @output = input.int
          @stale = input.boolean?
        end
      end
    end
  end
end
