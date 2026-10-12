# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # The drive's own fields in a keyed snapshot module (BL-D8): its
      # model, its clock phase, its cycle count, the 555's count to its
      # next pulse and the byte the gate array latched.
      module KeyedState
        def save_fields(out)
          out.text("model", model_name).int("phase", @phase).int("cycles", @cycles).int("irq_timer", @irq_timer)
          out.int("latched_byte", @mechanism.latched_byte)
        end

        def load_fields(input)
          input.choice("model", [model_name], model_name)
          @phase = input.int("phase", @phase)
          @cycles = input.int("cycles", @cycles)
          @irq_timer = input.int("irq_timer", @irq_timer).clamp(1, IRQ_PERIOD)
          @mechanism.latched_byte = input.byte("latched_byte", @mechanism.latched_byte)
        end

        # The drive as modules of its own, named from `name` (BL-D8 for
        # device 8): its own fields, its RAM, the CPU's port, the drive's
        # TIA, its interface's TIA in the computer, the CPU, the mechanism
        # and the disk, when one is in.
        def save_modules(sections, name)
          sections << Snapshot::Keyed.section(name) { |out| save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-RAM") { |out| @bus.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-PORT") { |out| @port.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-TIA") { |out| @tia.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-HOSTTIA") { |out| @host_tia.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-CPU") { |out| @cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("#{name}-MECH") { |out| @mechanism.save_fields(out) }
          disk = @mechanism.disk
          sections << Snapshot::Keyed.section("#{name}-DISK") { |out| disk.save_fields(out) } if disk
          sections
        end

        # The drive from its modules, `input` being its own. No disk module
        # means no disk in the drive. The cable's lines and the mechanism's
        # mode follow the TIAs once both are loaded.
        def load_modules(modules, input, name)
          load_fields(input)
          @bus.load_fields(modules.required("#{name}-RAM"))
          @port.load_fields(modules.required("#{name}-PORT"))
          @tia.load_fields(modules.required("#{name}-TIA"))
          @host_tia.load_fields(modules.required("#{name}-HOSTTIA"))
          @cpu.load_fields(modules.required("#{name}-CPU"))
          disk_input = modules.optional("#{name}-DISK")
          disk = disk_input.nil? ? nil : Model1541::Disk.from_fields(disk_input, detached: modules.detached?)
          @mechanism.load_fields(modules.required("#{name}-MECH"), disk)
          @cable.moved
          @cpu.restored!
        end
      end

      include KeyedState
    end
  end
end
