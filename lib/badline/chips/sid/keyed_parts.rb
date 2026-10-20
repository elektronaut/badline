# frozen_string_literal: true

module Badline
  module Chips
    class SID
      class Waveform
        # An oscillator's fields in a keyed snapshot module, under `prefix`:
        # the phase, the noise register and its pipeline, the delayed
        # shapers, the sync edge, the floating output and the pulse level.
        # What the registers set comes from them on load.
        module KeyedState
          # The fields reSID keeps for an oscillator between cycles, for VICE's
          # SIDEXTENDED module: the phase, the noise register, its shift pipeline
          # and reset countdown, the floating output's countdown and the pulse
          # level.
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

          def save_fields(out, prefix)
            out.int("#{prefix}accumulator", @accumulator).int("#{prefix}shift_register", @shift_register)
            out.int("#{prefix}shift_register_reset", @shift_register_reset)
            out.int("#{prefix}shift_pipeline", @shift_pipeline).int("#{prefix}delayed_triangle", @delayed_triangle)
            out.int("#{prefix}delayed_sawtooth", @delayed_sawtooth).bool("#{prefix}msb_rising", @msb_rising)
            out.int("#{prefix}floating", @floating).int("#{prefix}floating_ttl", @floating_ttl)
            out.int("#{prefix}pulse", @pulse)
          end

          def load_fields(input, prefix)
            @accumulator = input.masked("#{prefix}accumulator", @accumulator, 0xffffff)
            @shift_register = input.masked("#{prefix}shift_register", @shift_register, 0x7fffff)
            @shift_register_reset = input.int("#{prefix}shift_register_reset", @shift_register_reset)
            @shift_pipeline = input.int("#{prefix}shift_pipeline", @shift_pipeline)
            @delayed_triangle = input.masked("#{prefix}delayed_triangle", @delayed_triangle, 0xfff)
            @delayed_sawtooth = input.masked("#{prefix}delayed_sawtooth", @delayed_sawtooth, 0xfff)
            @msb_rising = input.bool("#{prefix}msb_rising", @msb_rising)
            @floating = input.masked("#{prefix}floating", @floating, 0xfff)
            @floating_ttl = input.int("#{prefix}floating_ttl", @floating_ttl)
            @pulse = input.masked("#{prefix}pulse", @pulse, 0xfff)
          end

          # The frequency, pulse width and control bits as the registers
          # hold them, without the test bit's or the waveform change's
          # effects on the noise register, which already happened.
          def restore_registers(frequency, pulse_width, control)
            @frequency = frequency
            @pulse_width = pulse_width & 0xfff
            @selected = (control >> 4) & 0x0f
            @test = control.anybits?(0x08)
            @ring = control.anybits?(0x04)
            @sync = control.anybits?(0x02)
            @stale = true
          end
        end

        include KeyedState
      end

      class Envelope
        # The envelope generator's fields in a keyed snapshot module, under
        # `prefix`: the state, the counters and pipelines between them. The
        # rates and the gate come from the registers on load.
        module KeyedState
          # The fields reSID keeps for an envelope between cycles, for VICE's
          # SIDEXTENDED module: the rate and exponential counters, the level, the
          # state as an index into STATES, whether it holds at zero, the two
          # periods and the pipeline.
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

          def save_fields(out, prefix)
            out.text("#{prefix}state", @state.to_s).text("#{prefix}next_state", @next_state.to_s)
            out.int("#{prefix}counter", @counter).int("#{prefix}env3", @env3)
            out.int("#{prefix}rate_counter", @rate_counter)
            out.int("#{prefix}rate_period", @rate_period).bool("#{prefix}reset_rate_counter", @reset_rate_counter)
            out.int("#{prefix}exponential_counter", @exponential_counter)
            out.int("#{prefix}exponential_period", @exponential_period)
            out.int("#{prefix}state_pipeline", @state_pipeline).int("#{prefix}envelope_pipeline", @envelope_pipeline)
            out.int("#{prefix}exponential_pipeline", @exponential_pipeline).bool("#{prefix}hold_zero", @hold_zero)
          end

          def load_fields(input, prefix)
            @state = state_named(input.choice("#{prefix}state", STATE_NAMES, @state.to_s))
            @next_state = state_named(input.choice("#{prefix}next_state", STATE_NAMES, @next_state.to_s))
            @counter = input.byte("#{prefix}counter", @counter)
            @env3 = input.byte("#{prefix}env3", @env3)
            @rate_counter = input.masked("#{prefix}rate_counter", @rate_counter, 0x7fff)
            @rate_period = input.int("#{prefix}rate_period", @rate_period)
            @reset_rate_counter = input.bool("#{prefix}reset_rate_counter", @reset_rate_counter)
            load_pipeline_fields(input, prefix)
          end

          # The rates and the gate as the registers hold them.
          def restore_registers(attack_decay, sustain_release, control)
            @attack = (attack_decay >> 4) & 0x0f
            @decay = attack_decay & 0x0f
            @sustain = (sustain_release >> 4) & 0x0f
            @release = sustain_release & 0x0f
            @gate = control.anybits?(0x01)
          end

          private

          def load_pipeline_fields(input, prefix)
            @exponential_counter = input.int("#{prefix}exponential_counter", @exponential_counter)
            @exponential_period = input.int("#{prefix}exponential_period", @exponential_period)
            @state_pipeline = input.int("#{prefix}state_pipeline", @state_pipeline)
            @envelope_pipeline = input.int("#{prefix}envelope_pipeline", @envelope_pipeline)
            @exponential_pipeline = input.int("#{prefix}exponential_pipeline", @exponential_pipeline)
            @hold_zero = input.bool("#{prefix}hold_zero", @hold_zero)
          end

          def state_named(name)
            case name
            when "attack" then :attack
            when "decay_sustain" then :decay_sustain
            else :release
            end
          end
        end

        STATE_NAMES = STATES.map(&:to_s).freeze

        include KeyedState
      end

      class Voice
        # A voice's oscillator under `prefix`wave. and its envelope under
        # `prefix`env.
        module KeyedState
          def save_fields(out, prefix)
            @waveform.save_fields(out, "#{prefix}wave.")
            @envelope.save_fields(out, "#{prefix}env.")
          end

          def load_fields(input, prefix)
            @waveform.load_fields(input, "#{prefix}wave.")
            @envelope.load_fields(input, "#{prefix}env.")
          end
        end

        include KeyedState
      end

      class Filter
        class External
          # The output filter's integrators and output, under `prefix`.
          module KeyedState
            def save_fields(out, prefix)
              out.int("#{prefix}lowpass", @lowpass).int("#{prefix}highpass", @highpass).int("#{prefix}output", @output)
            end

            def load_fields(input, prefix)
              @lowpass = input.int("#{prefix}lowpass", @lowpass)
              @highpass = input.int("#{prefix}highpass", @highpass)
              @output = input.int("#{prefix}output", @output)
            end
          end

          include KeyedState
        end

        # The filter's integrators and its last input, under `prefix`, and
        # the output filter's under ext. The cutoff, resonance, routing,
        # mode and volume come from the registers on load.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}highpass", @highpass).int("#{prefix}bandpass", @bandpass)
            out.int("#{prefix}lowpass", @lowpass).int("#{prefix}unfiltered", @unfiltered).int("#{prefix}input", @input)
            @external.save_fields(out, "ext.")
          end

          def load_fields(input, prefix)
            @highpass = input.int("#{prefix}highpass", @highpass)
            @bandpass = input.int("#{prefix}bandpass", @bandpass)
            @lowpass = input.int("#{prefix}lowpass", @lowpass)
            @unfiltered = input.int("#{prefix}unfiltered", @unfiltered)
            @input = input.int("#{prefix}input", @input)
            @external.load_fields(input, "ext.")
          end

          # $D415 to $D418 as written.
          def restore_registers(cutoff_low, cutoff_high, resonance, mode_volume)
            self.cutoff = (cutoff_high << 3) | (cutoff_low & 0x07)
            write_resonance(resonance)
            write_mode_volume(mode_volume)
          end
        end

        include KeyedState
      end

      # The SID's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers as written, the data bus latch and its decay, each
      # voice's under voice1. to voice3., and the filter's under filter.
      # and ext. Saving catches the DSP up first, so no span or deferred
      # write is left to save. What the registers decode to is worked out
      # from them on load. A recording SID also saves how far its recording
      # has got under rec., with the rate, the clock and the filter chunk it
      # records at: the samples' windows bound the filter's steps, so a SID
      # loaded from it that records at the same rate and clock carries on
      # from that window and integrates the steps the saved one does.
      module KeyedState
        def save_fields(out)
          catch_up
          out.bytes("registers", @registers.read(0, 0x20)).int("bus_value", @bus_value).int("bus_ttl", @bus_ttl)
          @voice1.save_fields(out, "voice1.")
          @voice2.save_fields(out, "voice2.")
          @voice3.save_fields(out, "voice3.")
          @filter.save_fields(out, "filter.")
          recording = @decimator || @resumed_recording
          save_recording(out, recording) if recording
          out
        end

        def load_fields(input)
          @registers.write(0, input.bytes_into("registers", @registers.read(0, 0x20)))
          @bus_value = input.byte("bus_value", @bus_value)
          @bus_ttl = input.int("bus_ttl", @bus_ttl)
          @pending_cycles = 0
          @deferred_writes.clear
          @voice1.load_fields(input, "voice1.")
          @voice2.load_fields(input, "voice2.")
          @voice3.load_fields(input, "voice3.")
          @filter.load_fields(input, "filter.")
          load_recording(input)
        end

        def restored!
          restore_voice(@voice1, 0x00)
          restore_voice(@voice2, 0x07)
          restore_voice(@voice3, 0x0e)
          @filter.restore_registers(register(0x15), register(0x16), register(0x17), register(0x18))
          update_span_rules
        end

        private

        def save_recording(out, decimator)
          out.int("rec.rate", decimator.rate).int("rec.clock_hz", decimator.clock_hz)
          out.int("rec.filter_chunk", @filter_chunk)
          decimator.save_fields(out, "rec.")
        end

        def load_recording(input)
          @resumed_recording = nil
          rate = input.int("rec.rate", 0)
          return unless rate.positive?

          @filter_chunk = input.int("rec.filter_chunk", @filter_chunk)
          decimator = Decimator.new(clock_hz: input.int("rec.clock_hz", Region::PAL.clock_hz), rate:)
          decimator.load_fields(input, "rec.")
          @resumed_recording = decimator
        end

        # The window a loaded snapshot's recording had got to, when this
        # recording is at its rate, clock and filter chunk.
        def resumed_recording(rate, filter_chunk, clock_hz)
          resumed = @resumed_recording
          @resumed_recording = nil
          return if resumed.nil? || filter_chunk != @filter_chunk

          resumed if resumed.rate == rate && resumed.clock_hz == clock_hz
        end

        def restore_voice(voice, base)
          control = register(base + 4)
          voice.waveform.restore_registers(register(base) | (register(base + 1) << 8),
                                           register(base + 2) | (register(base + 3) << 8), control)
          voice.envelope.restore_registers(register(base + 5), register(base + 6), control)
        end
      end

      include KeyedState
    end
  end
end
