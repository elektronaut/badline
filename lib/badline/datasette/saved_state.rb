# frozen_string_literal: true

module Badline
  class Datasette
    # The datasette's state for a snapshot.
    module SavedState
      # The keys, the motor, the countdown to the next pulse and the tape:
      # its path, its bytes and how far it has played.
      def save_state(out)
        out.marker("DATASETTE")
        out.boolean(@playing).boolean(@motor).int(@countdown).boolean(!@tape.nil?)
        return unless @tape

        out.string(@tape.path).blob(@tape.bytes).int(@tape.position)
      end

      # The tape goes back in from the bytes the state holds, without its
      # host file, unless the tape in is the same one. The sense and flag
      # handlers don't fire.
      def load_state(input)
        input.marker("DATASETTE")
        @playing = input.boolean?
        @motor = input.boolean?
        @countdown = input.int
        return @tape = nil unless input.boolean?

        path = input.string
        bytes = input.blob
        position = input.int
        @tape = Storage::TAP.new(path, bytes:) unless @tape&.path&.b == path && @tape.bytes == bytes
        @tape.position = position
      end
    end
  end
end
