# frozen_string_literal: true

module Badline
  class SID
    # The SID's state for a snapshot.
    module SavedState
      # How far the recording has got into the sample it is averaging, for
      # a host that carries on recording from a saved state: it calls
      # #record, then #load_recording.
      def save_recording(out)
        decimator = @decimator
        raise ArgumentError, "the SID isn't recording" if decimator.nil?

        out.marker("RECORDING")
        decimator.save_state(out)
      end

      def load_recording(input)
        decimator = @decimator
        raise ArgumentError, "the SID isn't recording" if decimator.nil?

        input.marker("RECORDING")
        decimator.load_state(input)
      end

      # The registers, the data bus, the voices and the filter, and the span
      # the DSP has yet to catch up on, as it stands: saving leaves the SID
      # as it was. Whether it synthesizes or records is the host's.
      def save_state(out)
        out.marker("SID")
        @registers.save_state(out)
        out.int(@bus_value).int(@bus_ttl).int(@pending_cycles).ints(@deferred_writes)
        @voices.each { |voice| voice.save_state(out) }
        @filter.save_state(out)
      end

      def load_state(input)
        input.marker("SID")
        @registers.load_state(input)
        @bus_value = input.int
        @bus_ttl = input.int
        @pending_cycles = input.int
        input.ints_into(@deferred_writes)
        @voices.each { |voice| voice.load_state(input) }
        @filter.load_state(input)
        update_span_rules
      end
    end
  end
end
