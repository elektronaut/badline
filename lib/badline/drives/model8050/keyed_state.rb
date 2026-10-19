# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      class Disk
        # A disk's fields in a keyed snapshot module (BL-D8-DISK, BL-D8-DISK1
        # for drive 1): the image file's path and how it was opened, the
        # image as last flushed, embedded under image and image.format, each
        # track whose cells differ from what the image lays out, as
        # track<N>, a cell per byte or 256 for a sync, and the tracks
        # written since the last flush.
        module KeyedState
          IMAGE_FORMATS = %w[d80 d82].freeze

          def save_fields(out)
            image = @image
            out.text("path", image.path.to_s).bool("read_only", image.read_only?)
            out.text("image.format", image_format)
            out.bytes("image", image.contents)
            @tracks.each do |number, cells|
              out.ints("track#{number}", cells) unless cells == build(number)
            end
            out.ints("written", @written.keys)
          end

          # Puts back the tracks and the writes not yet flushed.
          def load_track_fields(input)
            (1..(side_tracks * sides)).each do |number|
              cells = input.ints("track#{number}", [])
              @tracks[number] = cells.dup unless cells.empty?
            end
            input.ints("written", []).each { |number| @written[number] = true }
            self
          end
        end

        include KeyedState

        # The kind of image the disk lays out, as image.format names it.
        def image_format = @image.is_a?(Storage::D82Image) ? "d82" : "d80"

        # The disk a BL-D8-DISK module holds. A detached reader gets the
        # image write-protected, and it and a host file that is gone leave
        # it no path to write back to.
        def self.from_fields(input, detached: false)
          path = input.text("path", "")
          read_only = input.bool("read_only", false) || detached
          kind = input.choice("image.format", KeyedState::IMAGE_FORMATS, "d80")
          bytes = input.bytes("image", "".b).bytes
          path = "" if detached || !File.file?(path)
          image_class = kind == "d82" ? Storage::D82Image : Storage::D80Image
          new(image_class.new(path, read_only:, bytes:)).load_track_fields(input)
        end
      end

      class Mechanism
        # The drives' fields in a keyed snapshot module (BL-D8-MECH), a value
        # a drive in each list: the heads' cylinders, the stepper phases,
        # each disk's place in its turn and its bit clock, the disk change
        # under way and the motors, then the byte ready pulse, the byte on
        # VIA port A and SYNC. The disks load from their own modules.
        module KeyedState
          def save_fields(out)
            out.ints("cylinders", @cylinders).ints("phases", @phases).ints("positions", @positions)
            out.ints("bit_clocks", @clocks).ints("changing", @changing)
            out.ints("motors", @motors.map { |on| on ? 1 : 0 }).ints("syncs", @syncs.map { |low| low ? 1 : 0 })
            out.bool("so_pending", @so_pending).bool("ca1_low", @ca1_low).int("data_in", @data_in)
          end

          def load_fields(input, disks)
            @disks = disks
            input.ints_into("cylinders", @cylinders)
            input.ints_into("phases", @phases)
            input.ints_into("positions", @positions)
            input.ints_into("bit_clocks", @clocks)
            input.ints_into("changing", @changing)
            @motors = input.ints("motors", [0, 0]).map { |on| on == 1 }
            @syncs = input.ints("syncs", [0, 0]).map { |low| low == 1 }
            @so_pending = input.bool("so_pending", @so_pending)
            @ca1_low = input.bool("ca1_low", @ca1_low)
            @data_in = input.byte("data_in", @data_in)
          end
        end

        include KeyedState
      end

      # The unit's own fields in a keyed snapshot module (BL-D8): its model,
      # its clock phase and cycle count, each bus's last byte, and the
      # controller's lines as the port latched them, under ieee.*. A save
      # settles the unit first, so it is awake; a load finds its passes
      # afresh.
      module KeyedState
        def save_fields(out)
          settle!
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles)
          out.int("ip_data", @ip_bus.data).int("fdc_data", @fdc_bus.data)
          out.int("ieee.host", @ieee_port.host)
          out
        end

        def load_fields(input)
          settle!
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @ip_bus.data = input.byte("ip_data", @ip_bus.data)
          @fdc_bus.data = input.byte("fdc_data", @fdc_bus.data)
          @ieee_port.host = input.int("ieee.host", @ieee_port.host)
        end

        # The unit as modules of its own, named from `name` (BL-D8 for
        # device 8): its own fields, the common RAM, UC1 and UE1 with their
        # RAM, each processor, the VIA, the 6530, the drives and each disk
        # in, drive 1's as -DISK1.
        def save_modules(sections, name)
          sections << Snapshot::Keyed.section(name) { |out| save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-COMMON") { |out| @common.save_fields(out, "ram") }
          sections << Snapshot::Keyed.section("#{name}-RIOT1") { |out| @data_riot.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RIOT2") { |out| @control_riot.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-IPCPU") { |out| @ip_cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-FDCCPU") { |out| @fdc_cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-VIA") { |out| @via.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RRIOT") { |out| @rriot.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-MECH") { |out| @mechanism.save_fields(out) }
          [0, 1].each do |drive|
            disk = @mechanism.disk(drive)
            sections << Snapshot::Keyed.section(disk_module(name, drive)) { |out| disk.save_fields(out) } if disk
          end
          sections
        end

        # The unit from its modules, `input` being its own. No disk module
        # means no disk in that drive.
        def load_modules(modules, input, name)
          load_fields(input)
          @common.load_fields(modules.required("#{name}-COMMON"), "ram")
          @data_riot.load_fields(modules.required("#{name}-RIOT1"))
          @control_riot.load_fields(modules.required("#{name}-RIOT2"))
          @ip_cpu.load_fields(modules.required("#{name}-IPCPU"))
          @fdc_cpu.load_fields(modules.required("#{name}-FDCCPU"))
          @via.load_fields(modules.required("#{name}-VIA"))
          @rriot.load_fields(modules.required("#{name}-RRIOT"))
          disks = [0, 1].map do |drive|
            disk = modules.optional(disk_module(name, drive))
            disk.nil? ? nil : disk_from_fields(disk, modules.detached?)
          end
          @mechanism.load_fields(modules.required("#{name}-MECH"), disks)
          @via.restored!
          @ip_cpu.restored!
          @fdc_cpu.restored!
        end

        private

        def disk_module(name, drive) = drive.zero? ? "#{name}-DISK" : "#{name}-DISK1"
      end

      include KeyedState
    end
  end
end
