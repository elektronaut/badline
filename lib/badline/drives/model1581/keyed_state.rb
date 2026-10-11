# frozen_string_literal: true

module Badline
  module Drives
    class Model1581
      class WD1772
        PHASE_NAMES = %w[idle spin_up stepped settled search read_data write_gate write_data read_track track_index
                         write_track motor_idle index_interrupt settle_search read_address write_track_start
                         starting].freeze
        MODE_NAMES = %w[read write address verify_track].freeze

        # The controller in a keyed snapshot module (BL-D8-FDC): its own
        # cycle count, the step of the command running and what the search
        # is for by name, the registers and lines, the command's counters,
        # and when its next step, its deadline and the next ID field fall,
        # in its cycles from now, each absent when it never does.
        def save_fields(out)
          out.int("now", @now).text("phase", PHASE_NAMES.fetch(@phase)).text("mode", MODE_NAMES.fetch(@mode))
          [["due_in", @due], ["deadline_in", @deadline], ["id_in", @id_at]].each do |key, at|
            out.int(key, at - @now) unless at == NEVER
          end
          out.int("command", @command).int("track", @track).int("sector", @sector).int("data", @data)
          out.int("status", @status).int("steps", @steps).int("count", @count).int("after_spin_up", @after_spin_up)
          out.int("found", @found).int("index", @index).int("crc", @crc).int("write_id", @write_id).int("size", @size)
          save_flag_fields(out)
          out.bytes("bytes", @bytes).ints("syncs", @syncs.map { |sync| sync ? 1 : 0 })
        end

        def load_fields(input)
          @now = input.int("now", @now)
          @phase = PHASE_NAMES.index(input.choice("phase", PHASE_NAMES, "idle")).to_i
          @mode = MODE_NAMES.index(input.choice("mode", MODE_NAMES, "read")).to_i
          @due = at_fields(input, "due_in")
          @deadline = at_fields(input, "deadline_in")
          @id_at = at_fields(input, "id_in")
          load_register_fields(input)
          load_flag_fields(input)
          @bytes = input.bytes("bytes", "".b).bytes
          @syncs = input.ints("syncs", []).map { |sync| sync == 1 }
        end

        private

        def at_fields(input, key)
          cycles = input.optional_int(key)
          cycles.nil? ? NEVER : @now + cycles
        end

        def load_register_fields(input)
          @command = input.byte("command", @command)
          @track = input.byte("track", @track)
          @sector = input.byte("sector", @sector)
          @data = input.byte("data", @data)
          @status = input.byte("status", @status)
          @steps = input.int("steps", @steps)
          @count = input.int("count", @count)
          @after_spin_up = input.int("after_spin_up", @after_spin_up)
          @found = input.int("found", @found)
          @index = input.int("index", @index)
          @crc = input.int("crc", @crc)
          @write_id = input.int("write_id", @write_id)
          @size = input.int("size", @size)
        end

        def save_flag_fields(out)
          out.bool("type1", @type1).bool("drq", @drq).bool("intrq", @intrq).bool("motor_on", @motor_on)
          out.bool("inward", @inward).bool("crc_good", @crc_good).bool("gate_open", @gate_open).bool("late", @late)
          out.bool("settling", @settling)
        end

        def load_flag_fields(input)
          @type1 = input.bool("type1", @type1)
          @drq = input.bool("drq", @drq)
          @intrq = input.bool("intrq", @intrq)
          @motor_on = input.bool("motor_on", @motor_on)
          @inward = input.bool("inward", @inward)
          @crc_good = input.bool("crc_good", @crc_good)
          @gate_open = input.bool("gate_open", @gate_open)
          @late = input.bool("late", @late)
          @settling = input.bool("settling", @settling)
        end
      end

      class Mechanism
        # The head, the motor and the disk-change switch in a keyed snapshot
        # module (BL-D8-MECH), with the disk's angle as it stands `now`, on
        # the controller's clock.
        def save_fields(out, now)
          out.int("cylinder", @cylinder).int("side", @side).int("angle", angle(now)).bool("motor", @motor)
          out.bool("changed", @changed)
        end

        # Puts `disk` under the head without flushing the one there, as a
        # snapshot load replaces it.
        def load_fields(input, disk, now)
          @disk = disk
          @cylinder = input.int("cylinder", @cylinder)
          @side = input.masked("side", @side, 1)
          @angle = input.int("angle", @angle)
          @since = now
          @motor = input.bool("motor", @motor)
          @changed = input.bool("changed", @changed)
        end
      end

      class Disk
        # A disk's fields in a keyed snapshot module (BL-D8-DISK): the image
        # file's path and how it was opened, the image as last flushed,
        # embedded, each track the head wrote since the disk went in, sector
        # by sector as the WD1772 sees them, and the tracks written since the
        # last flush.
        module KeyedState
          # The image's path, expanded, and whether it was opened read-only,
          # for a disk from Disk.open. Nil for a disk made another way.
          attr_reader :path, :read_only

          # Notes the image's path and how it was opened.
          def opened(path, read_only)
            @path = File.expand_path(path)
            @read_only = read_only
            self
          end

          def save_fields(out)
            path = @path
            out.text("path", path) if path
            out.bool("read_only", @read_only == true)
            image = @image
            out.text("image.path", image.path.to_s).bytes("image", image.contents) if image
            changed = @changed.keys.sort
            out.ints("changed", changed)
            changed.each { |index| save_track_fields(out, "track#{index}.", @tracks[index]) }
            out.ints("written", @written.keys)
          end

          def load_track_fields(input)
            @changed.clear
            input.ints("changed", []).each do |index|
              @tracks[index] = load_track_sectors(input, "track#{index}.")
              @changed[index] = true
            end
            @written.clear
            input.ints("written", []).each { |index| @written[index] = true }
            self
          end

          private

          def save_track_fields(out, prefix, track)
            out.int("#{prefix}sectors", track.sectors.length)
            track.sectors.each_with_index do |sector, number|
              save_field_fields(out, "#{prefix}sector#{number}.id.", sector.id)
              data = sector.data
              save_field_fields(out, "#{prefix}sector#{number}.data.", data) if data
            end
          end

          def save_field_fields(out, prefix, field)
            out.int("#{prefix}mark", field.mark).bytes("#{prefix}bytes", field.bytes)
            out.bool("#{prefix}good", field.good).bool("#{prefix}deleted", field.deleted)
          end

          def load_track_sectors(input, prefix)
            Track.new(Array.new(input.int("#{prefix}sectors", 0)) do |number|
              id = load_field_fields(input, "#{prefix}sector#{number}.id.")
              data = input.optional_int("#{prefix}sector#{number}.data.mark")
              Track::Sector.new(id, data.nil? ? nil : load_field_fields(input, "#{prefix}sector#{number}.data."))
            end)
          end

          def load_field_fields(input, prefix)
            Track::Field.new(input.int("#{prefix}mark", 0), input.bytes("#{prefix}bytes", "".b).bytes,
                             input.bool("#{prefix}good", true), input.bool("#{prefix}deleted", false))
          end
        end

        include KeyedState

        # The disk a keyed snapshot module describes: its embedded image,
        # with the tracks the module holds laid over it. The image takes
        # writes back to its file only while that file is there and the
        # reader isn't `detached`. With no image, the disk is the tracks
        # alone.
        def self.from_fields(input, detached: false)
          path = input.text("path", "")
          read_only = input.bool("read_only", false)
          bytes = input.bytes("image", "".b).bytes
          image_path = input.text("image.path", "")
          disk = bytes.empty? ? Disk.new : Disk.new(image_from(image_path, bytes, read_only || detached))
          disk.opened(path, read_only || bytes.empty?) unless path.empty?
          disk.load_track_fields(input)
        end

        def self.image_from(path, bytes, read_only)
          Storage::D81Image.new(File.file?(path) ? path : "", read_only:, bytes:)
        end
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

      # The drive's own fields in a keyed snapshot module (BL-D8): its
      # model, its clock phase and cycle count, the ATN level it last saw
      # and the host's lines as the serial port latched them. The fast
      # serial direction and the ports' lines come from the 8520 once it
      # is loaded.
      module KeyedState
        def save_fields(out)
          settle!
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles).bool("atn", @atn)
          @serial_port.save_fields(out, "serial.")
          out
        end

        def load_fields(input)
          settle!
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @atn = input.bool("atn", @atn)
          @serial_port.load_fields(input, "serial.")
        end

        def restored!
          @fast_serial_out = @cia.port_b_lines.anybits?(FAST_SERIAL_OUT)
          ports_written
          push_fast_output(@fast_serial_out ? fast_pins : 0)
          forget_orbits
        end

        # The drive as modules of its own, as the 1541's, with the 8520 and
        # the WD1772 in place of the VIAs.
        def save_modules(sections, name)
          sections << Snapshot::Keyed.section(name) { |out| save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RAM") { |out| @bus.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-CIA") { |out| @cia.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-CPU") { |out| @cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-FDC") { |out| @fdc.save_fields(out) }
          now = @fdc.now
          sections << Snapshot::Keyed.section("#{name}-MECH") { |out| @mechanism.save_fields(out, now) }
          disk = @mechanism.disk
          sections << Snapshot::Keyed.section("#{name}-DISK") { |out| disk.save_fields(out) } if disk
          sections
        end

        # The drive from its modules, `input` being its own. The mechanism
        # takes the disk's angle on the WD1772's clock, so it loads after
        # the controller.
        def load_modules(modules, input, name)
          load_fields(input)
          @bus.load_fields(modules.required("#{name}-RAM"))
          @cia.load_fields(modules.required("#{name}-CIA"))
          @cpu.load_fields(modules.required("#{name}-CPU"))
          @fdc.load_fields(modules.required("#{name}-FDC"))
          disk = modules.optional("#{name}-DISK")
          mechanism = modules.required("#{name}-MECH")
          @mechanism.load_fields(mechanism, disk.nil? ? nil : Disk.from_fields(disk, detached: modules.detached?),
                                 @fdc.now)
          @cia.restored!
          @cpu.restored!
          restored!
        end
      end

      include KeyedState
    end
  end
end
