# frozen_string_literal: true

module Badline
  class SID
    class Filter
      # The filter's state for a snapshot.
      module SavedState
        # The registers as the filter decoded them and its integrators. The
        # W0 table is the model's.
        def save_state(out)
          out.int(@cutoff).int(@routing).int(@mode).int(@volume).boolean(@voice3_off).int(@w0).int(@resonance)
          [@highpass, @bandpass, @lowpass, @unfiltered, @input].each { |value| out.int(value) }
          @external.save_state(out)
        end

        def load_state(input)
          @cutoff = input.int
          @routing = input.int
          @mode = input.int
          @volume = input.int
          @voice3_off = input.boolean?
          @w0 = input.int
          @resonance = input.int
          load_integrators(input)
        end

        private

        def load_integrators(input)
          @highpass = input.int
          @bandpass = input.int
          @lowpass = input.int
          @unfiltered = input.int
          @input = input.int
          @external.load_state(input)
        end
      end
    end
  end
end
