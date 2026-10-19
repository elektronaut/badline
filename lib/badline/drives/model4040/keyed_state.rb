# frozen_string_literal: true

module Badline
  module Drives
    class Model4040
      class Disk
        def image_format = "d64"

        # The disk a BL-D8-DISK module holds, as Model8050::Disk's, from a
        # .d64.
        def self.from_fields(input, detached: false)
          path = input.text("path", "")
          read_only = input.bool("read_only", false) || detached
          input.choice("image.format", %w[d64], "d64")
          bytes = input.bytes("image", "".b).bytes
          path = "" if detached || !File.file?(path)
          new(Storage::D64Image.new(path, read_only:, bytes:)).load_track_fields(input)
        end
      end

      class Mechanism
        # The drives' fields in a keyed snapshot module (BL-D8-MECH), a value
        # a drive in each list: the heads' half tracks, the stepper counts,
        # each disk's place in its turn and its bit clock and the motors,
        # then byte ready, the byte on VIA port A and SYNC. The disks load
        # from their own modules.
        module KeyedState
          def save_fields(out)
            out.ints("half_tracks", @half_tracks).ints("phases", @phases).ints("positions", @positions)
            out.ints("bit_clocks", @clocks)
            out.ints("motors", @motors.map { |on| on ? 1 : 0 }).ints("syncs", @syncs.map { |low| low ? 1 : 0 })
            out.bool("ca1_low", @ca1_low).int("data_in", @data_in)
          end

          def load_fields(input, disks)
            @disks = disks
            input.ints_into("half_tracks", @half_tracks)
            input.ints_into("phases", @phases)
            input.ints_into("positions", @positions)
            input.ints_into("bit_clocks", @clocks)
            @motors = input.ints("motors", [0, 0]).map { |on| on == 1 }
            @syncs = input.ints("syncs", [0, 0]).map { |low| low == 1 }
            @ca1_low = input.bool("ca1_low", @ca1_low)
            @data_in = input.byte("data_in", @data_in)
          end
        end

        include KeyedState
      end
    end
  end
end
