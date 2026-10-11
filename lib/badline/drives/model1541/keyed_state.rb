# frozen_string_literal: true

module Badline
  module Drives
    class Model1541
      class Disk
        # The kinds of image a disk embeds, by name.
        IMAGE_KINDS = %w[none d64 d71 g64].freeze

        # A disk's fields in a keyed snapshot module (BL-D8-DISK): the image
        # file's path and how it was opened, the image as last flushed,
        # embedded under image and image.kind, each half track that differs
        # from what the image decodes to, as track<H>.zone, track<H>.speeds
        # and track<H>.gcr, raw GCR as the head sees it, and the half tracks
        # written since the last flush.
        module KeyedState
          def save_fields(out)
            path = @path
            out.text("path", path) if path
            out.bool("read_only", @read_only == true)
            image = @image
            decoded = nil
            if image
              out.text("image.kind", Disk.image_kind(image)).text("image.path", image.path.to_s)
              out.bytes("image", image.contents)
              decoded = Disk.decode(image)
            end
            @tracks.each_with_index { |track, half| save_track_fields(out, half, track, decoded) }
            out.ints("written", @written.keys)
          end

          def load_track_fields(input)
            @tracks.each_index do |half|
              zone = input.optional_int("track#{half}.zone")
              next if zone.nil?

              speeds = input.ints("track#{half}.speeds", [])
              gcr = input.bytes("track#{half}.gcr", "".b).bytes
              @tracks[half] = Track.new(gcr, zone, speeds.empty? ? nil : speeds.dup)
            end
            @written.clear
            input.ints("written", []).each { |half| @written[half] = true }
            self
          end

          private

          def save_track_fields(out, half, track, decoded)
            return if track.nil?

            original = decoded&.track(half)
            return if original && original.zone == track.zone && original.speeds == track.speeds &&
                      original.bytes == track.bytes

            out.int("track#{half}.zone", track.zone)
            speeds = track.speeds
            out.ints("track#{half}.speeds", speeds) if speeds
            out.bytes("track#{half}.gcr", track.bytes)
          end
        end

        include KeyedState

        # The kind of `image`, by name.
        def self.image_kind(image)
          return "g64" if image.is_a?(Storage::G64Image)
          return "d71" if image.is_a?(Storage::D71Image)

          "d64"
        end

        # The tracks `image` holds, as an insert decodes them.
        def self.decode(image) = image.is_a?(Storage::G64Image) ? from_g64(image) : from_d64(image)

        # The disk a keyed snapshot module describes: its embedded image
        # decoded, with the tracks the module holds laid over it. The image
        # takes writes back to its file only while that file is there and
        # the reader isn't `detached`. With no image, the disk is the
        # tracks alone, write-protected.
        def self.from_fields(input, detached: false)
          path = input.text("path", "")
          read_only = input.bool("read_only", false)
          kind = input.choice("image.kind", IMAGE_KINDS, "none")
          image_path = input.text("image.path", "")
          disk = kind == "none" ? Disk.new : from_image(input, kind, image_path, read_only || detached)
          disk.opened(path, read_only || kind == "none") unless path.empty?
          disk.load_track_fields(input)
        end

        def self.from_image(input, kind, path, read_only)
          bytes = input.bytes("image", "".b).bytes
          writable_path = path.empty? || !File.file?(path) ? "" : path
          image = case kind
                  when "g64" then Storage::G64Image.new(writable_path, read_only:, bytes:)
                  when "d71" then Storage::D71Image.new(writable_path, read_only:, bytes:)
                  else Storage::D64Image.new(writable_path, read_only:, bytes:)
                  end
          decode(image)
        end
      end

      class Mechanism
        # The head, the motor, the stepper and the read and write
        # electronics in a keyed snapshot module (BL-D8-MECH): where the
        # head is, the disk's place in its turn, the read clock's next
        # clock in cycles from now, the shift registers and the flags. The
        # cell under the head, its width and the next event come from the
        # track and the time on load, the cell period from the zone, and
        # the write protection from the disk.
        module KeyedState
          def save_fields(out)
            out.int("half_track", @half_track).int("slip", @slip).int("side", @side_base).int("zone", @zone)
            out.int("time", @time).int("read_clock_in", @clock_at - @time).int("clocks", @clocks)
            out.int("shift", @shift).int("ones", @ones).int("bits", @bits).int("write_shift", @write_shift)
            out.bool("motor", @motor).bool("led", @led).bool("sync", @sync).bool("byte_ready", @byte_ready)
            out.bool("byte_latched", @byte_latched).bool("writing", @writing).bool("write_gate", @write_gate)
            out.bool("track_written", @track_written).optional_int("write_index", @write_index)
          end

          # Puts `disk` under the head without flushing the one there, as a
          # snapshot load replaces it.
          def load_fields(input, disk)
            @disk = disk
            load_head_fields(input)
            load_flag_fields(input)
            @clock = Track.cell(@zone)
            @protected = disk&.write_protected? || false
            track_written = input.bool("track_written", false)
            write_index = input.optional_int("write_index")
            load_track(@time)
            @track_written = track_written
            @write_index = write_index
          end

          private

          def load_head_fields(input)
            @half_track = input.int("half_track", @half_track)
            @slip = input.masked("slip", @slip, 0x03)
            @side_base = input.int("side", @side_base)
            @zone = input.masked("zone", @zone, 0x03)
            @time = input.int("time", @time)
            @clock_at = @time + input.int("read_clock_in", @clock_at - @time)
            @clocks = input.int("clocks", @clocks)
            @shift = input.int("shift", @shift)
            @ones = input.int("ones", @ones)
            @bits = input.int("bits", @bits)
            @write_shift = input.int("write_shift", @write_shift)
          end

          def load_flag_fields(input)
            @motor = input.bool("motor", @motor)
            @led = input.bool("led", @led)
            @sync = input.bool("sync", @sync)
            @byte_ready = input.bool("byte_ready", @byte_ready)
            @byte_latched = input.bool("byte_latched", @byte_latched)
            @writing = input.bool("writing", @writing)
            @write_gate = input.bool("write_gate", @write_gate)
          end
        end

        include KeyedState
      end

      class Bus
        # The drive's RAM and the byte last on its data bus, in a keyed
        # snapshot module (BL-D8-RAM).
        def save_fields(out)
          out.int("data", @data).bytes("ram", @ram.read(0, @ram.length))
        end

        def load_fields(input)
          @data = input.byte("data", @data)
          ram = @ram.read(0, @ram.length)
          @ram.write(0, input.bytes_into("ram", ram))
          @watching = false
        end
      end

      # The drive's own fields in a keyed snapshot module (BL-D8): its model,
      # its clock phase and cycle count, the SO pulse due, and the host's
      # lines as the serial port latched them. A save settles the drive first, so it is awake;
      # a load forgets its orbits, as the positional load does.
      module KeyedState
        def save_fields(out)
          settle!
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles)
          out.bool("so_pending", @mechanism.so_pending)
          @serial_port.save_fields(out, "serial.")
          out
        end

        def load_fields(input)
          settle!
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @mechanism.so_pending = input.bool("so_pending", @mechanism.so_pending)
          @serial_port.load_fields(input, "serial.")
        end

        def restored! = forget_orbits

        # The drive as modules of its own, named from `name` (BL-D8 for
        # device 8): its own fields, its RAM, each VIA, the CPU, the
        # mechanism and the disk, when one is in.
        def save_modules(sections, name)
          sections << Snapshot::Keyed.section(name) { |out| save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RAM") { |out| @bus.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-VIA1") { |out| @via1.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-VIA2") { |out| @via2.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-CPU") { |out| @cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-MECH") { |out| @mechanism.save_fields(out) }
          disk = @mechanism.disk
          sections << Snapshot::Keyed.section("#{name}-DISK") { |out| disk.save_fields(out) } if disk
          sections
        end

        # The drive from its modules, `input` being its own. No disk module
        # means no disk in the drive.
        def load_modules(modules, input, name)
          load_fields(input)
          @bus.load_fields(modules.required("#{name}-RAM"))
          @via1.load_fields(modules.required("#{name}-VIA1"))
          @via2.load_fields(modules.required("#{name}-VIA2"))
          @cpu.load_fields(modules.required("#{name}-CPU"))
          disk = modules.optional("#{name}-DISK")
          mechanism = modules.required("#{name}-MECH")
          @mechanism.load_fields(mechanism, disk.nil? ? nil : Disk.from_fields(disk, detached: modules.detached?))
          @via1.restored!
          @via2.restored!
          @cpu.restored!
          restored!
        end
      end

      include KeyedState
    end
  end
end
