# frozen_string_literal: true

module Badline
  module Drives
    class Model2031
      # The drive's own fields in a keyed snapshot module (BL-D8): its
      # model, its clock phase and cycle count, the SO pulse due, and the
      # controller's lines as the IEEE-488 port latched them under ieee.*. A
      # save settles the drive first, so it is awake; a load forgets its
      # orbits.
      module KeyedState
        def save_fields(out)
          settle!
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles)
          out.bool("so_pending", @mechanism.so_pending)
          @serial_port.save_fields(out, "ieee.")
          out
        end

        def load_fields(input)
          settle!
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @mechanism.so_pending = input.bool("so_pending", @mechanism.so_pending)
          @serial_port.load_fields(input, "ieee.")
        end

        # The drive as modules of its own, named from `name` (BL-D8 for
        # device 8): its own fields, its RAM, each VIA, the CPU, the
        # mechanism and the disk, when one is in, as the 1541's.
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
          @mechanism.load_fields(mechanism,
                                 disk.nil? ? nil : Model1541::Disk.from_fields(disk, detached: modules.detached?))
          @via1.restored!
          @via2.restored!
          @cpu.restored!
          forget_orbits
        end
      end

      include KeyedState
    end
  end
end
