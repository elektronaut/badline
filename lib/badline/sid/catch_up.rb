# frozen_string_literal: true

module Badline
  class SID
    # Running the DSP over the cycles that have passed since it last caught
    # up, in spans that fast-forward the voices and end on a whole cycle.
    module CatchUp
      private

      # Runs the cycles that have passed, landing each queued write on the
      # cycle the CPU wrote it on.
      def catch_up
        replayed = 0
        i = 0
        while i < @deferred_writes.length
          cycle = @deferred_writes[i]
          run(cycle - replayed)
          replayed = cycle
          apply_write(@deferred_writes[i + 1], @deferred_writes[i + 2])
          i += 3
        end
        run(@pending_cycles - replayed)
        @deferred_writes.clear
        @pending_cycles = 0
      end

      def run(cycles)
        while cycles != 0
          span = span(cycles)
          fast_forward(span - 1) if span > 1
          clock!(span)
          cycles -= span
        end
      end

      # The longest stretch that can be fast-forwarded. A combined waveform
      # feeding back into its own oscillator steps cycle by cycle, and a span
      # never runs past an MSB rise that hard-syncs the next voice, so both
      # land on a whole cycle.
      def span(cycles)
        return 1 if @stepped

        span = @synthesizing ? synthesis_span(cycles) : cycles
        return span unless @synced

        span = sync_span(@waveform1, span)
        span = sync_span(@waveform2, span)
        sync_span(@waveform3, span)
      end

      # The filter steps at most @filter_chunk cycles at a time, and never
      # across the end of a recorded sample.
      def synthesis_span(cycles)
        span = [cycles, @filter_chunk].min
        return span unless @decimator

        [@decimator.cycles_to_close, span].min
      end

      # Whether a span has to step, or watch for hard sync, only changes with
      # a voice's control register.
      def update_span_rules
        @stepped = @voices.any? { |voice| voice.waveform.stepped?(@synthesizing) }
        @synced = @voices.any? { |voice| voice.waveform.sync? }
      end

      def sync_span(waveform, span)
        return span unless waveform.sync_dest.sync?

        rise = waveform.cycles_to_msb_rise
        rise && rise < span ? rise : span
      end

      # Unrolled over the three voices: the per-cycle block calls cost
      # measurably on the synthesis path.
      def fast_forward(cycles)
        @voice1.fast_forward(cycles)
        @voice2.fast_forward(cycles)
        @voice3.fast_forward(cycles)
      end

      # The last cycle of a span, run whole. The filter integrates the span
      # from the voices' output at its end.
      def clock!(span)
        @voice1.cycle!
        @voice2.cycle!
        @voice3.cycle!
        @waveform1.synchronize!
        @waveform2.synchronize!
        @waveform3.synchronize!
        return unless @synthesizing

        @filter.cycle!(@voices, span)
        record_sample(span) if @decimator
      end

      def record_sample(span)
        sample = @decimator.push(current_sample, span)
        @samples << sample if sample
      end

      def current_sample
        sample = @filter.output / SAMPLE_DIVISOR
        return sample unless sample < -0x8000 || sample > 0x7fff

        sample.clamp(-0x8000, 0x7fff)
      end
    end
  end
end
