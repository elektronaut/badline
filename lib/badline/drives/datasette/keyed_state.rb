# frozen_string_literal: true

module Badline
  module Drives
    class Datasette
      # The datasette's fields in a keyed snapshot module (Snapshot::Keyed,
      # BL-TAPE): the keys, the motor, the countdown to the next pulse, and
      # a tape in it under tape.*: its path, its bytes and how far it has
      # played. A tape that isn't in leaves tape.* out. The sense and flag
      # handlers don't fire on load.
      module KeyedState
        def save_fields(out)
          out.bool("playing", @playing).bool("motor", @motor).int("countdown", @countdown)
          tape = @tape
          return out unless tape

          out.text("tape.path", tape.path.to_s).bytes("tape.bytes", tape.bytes).int("tape.position", tape.position)
        end

        # The tape goes back in from the bytes the module holds, without its
        # host file, unless the tape in is the same one.
        def load_fields(input)
          @playing = input.bool("playing", @playing)
          @motor = input.bool("motor", @motor)
          @countdown = input.int("countdown", @countdown)
          bytes = input.bytes("tape.bytes", "".b).bytes
          return @tape = nil if bytes.empty?

          path = input.text("tape.path", "")
          @tape = Storage::TAP.new(path, bytes:) unless @tape&.path.to_s == path && @tape&.bytes == bytes
          @tape&.position = input.int("tape.position", 0)
        end
      end

      include KeyedState
    end
  end
end
