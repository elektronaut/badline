# frozen_string_literal: true

module Badline
  module Audio
    # The states a subtune's renderer saved as it played, at the first
    # frame end past every `every` seconds, so that a seek starts from the
    # latest one at or before where it goes rather than from the subtune's
    # start. Whoever plays the subtune keeps them across its renderers, and
    # drops them for another subtune.
    class Checkpoints
      EVERY = 10.0

      def initialize(every: EVERY)
        @every = every
        @cycles = []
        @states = []
      end

      # Whether the frame ending `cycles` into the subtune is the first past
      # the next mark.
      def due?(cycles, clock_hz) = cycles >= ((@cycles.length + 1) * @every * clock_hz).round

      def keep(cycles, state)
        @cycles << cycles
        @states << state
      end

      # The state saved latest at or before `cycles`, or nil.
      def latest(cycles)
        index = @cycles.rindex { |at| at <= cycles }
        index.nil? ? nil : @states[index]
      end
    end
  end
end
