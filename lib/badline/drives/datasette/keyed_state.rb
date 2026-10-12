# frozen_string_literal: true

module Badline
  module Drives
    class Datasette
      # The datasette's fields in a keyed snapshot module (Snapshot::Keyed,
      # BL-TAPE): the keys, the motor, the countdown to the next pulse,
      # whether it records, the cycles since the write line's last edge and
      # that line's level, and a tape in it under tape.*: its path, its
      # bytes and how far it has played. A tape that isn't in leaves tape.* out. A datasette that
      # times the read line's level adds when in the countdown the line
      # rises, and whether a recording's low half wave is on the tape. The
      # sense and flag handlers don't fire on load.
      module KeyedState
        def save_fields(out)
          out.bool("playing", @playing).bool("motor", @motor).int("countdown", @countdown)
          out.bool("recording", @recording).int("since", @since).bool("write_high", @write_high)
          out.int("rise_at", @rise_at).bool("low_recorded", @low_recorded) if @level
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
          @recording = input.bool("recording", @recording)
          @since = input.int("since", @since)
          @write_high = input.bool("write_high", @write_high)
          @rise_at = input.int("rise_at", @rise_at)
          @low_recorded = input.bool("low_recorded", @low_recorded)
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
