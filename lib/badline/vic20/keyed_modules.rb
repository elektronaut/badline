# frozen_string_literal: true

module Badline
  class Vic20
    # The whole machine as keyed snapshot modules (Snapshot::Keyed), in the
    # order a load applies them, as C64::KeyedModules: BL-MACHINE with the
    # RAM expansion and the bytes each side's data lines hold under bus.*,
    # the memories, a cartridge's ROM chips, the VIC with its sound, both
    # VIAs, the CPU, the datasette, device 8 through the traps and the true
    # drives.
    module KeyedModules
      def save_modules
        bus = @bus
        sections = [Snapshot::Keyed.section("BL-MACHINE") do |out|
          save_machine_fields(out)
          bus.save_fields(out, "bus.")
        end]
        sections << Snapshot::Keyed.section("BL-RAM") { |out| bus.ram.save_fields(out, "ram") }
        sections << Snapshot::Keyed.section("BL-COLORRAM") { |out| bus.color_ram.save_fields(out, "ram") }
        sections << Snapshot::Keyed.section("BL-CART") { |out| bus.save_rom_fields(out) } if bus.cartridge?
        sections << Snapshot::Keyed.section("BL-CPU") { |out| @cpu.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-VICI") { |out| @vic.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-VIA1") { |out| @via1.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-VIA2") { |out| @via2.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TAPE") { |out| @datasette.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TRAPDOS") { |out| save_trap_dos_fields(out) } if mounted?
        save_drive_modules(sections)
      end

      # Raises Snapshot::FormatError for the modules of a VIC-20 with
      # another RAM expansion or of another model.
      def load_modules(modules)
        machine = modules.machine
        check_snapshot_setup(Snapshot::Vic20Setup.read_fields(machine))
        load_machine_fields(machine)
        bus = @bus
        bus.load_fields(machine, "bus.")
        bus.ram.load_fields(modules.required("BL-RAM"), "ram")
        bus.color_ram.load_fields(modules.required("BL-COLORRAM"), "ram")
        bus.load_rom_fields(modules.optional("BL-CART") || Snapshot::Keyed::Reader.new("BL-CART"))
        bus.restored!
        @vic.load_fields(modules.required("BL-VICI"))
        @via1.load_fields(modules.required("BL-VIA1"))
        @via2.load_fields(modules.required("BL-VIA2"))
        @cpu.load_fields(modules.required("BL-CPU"))
        @datasette.load_fields(modules.required("BL-TAPE"))
        trap_dos = modules.optional("BL-TRAPDOS")
        trap_dos ? load_trap_dos_fields(trap_dos, detached: modules.detached?) : unmount
        load_drive_modules(modules)
        modules_restored!
        self
      end

      private

      def modules_restored!
        @cpu.restored!
        @vic.restored!
        @via1.restored!
        @via2.restored!
        machine_restored!
      end

      def check_snapshot_setup(setup)
        unless setup.ram == @ram_configuration
          raise Snapshot::FormatError, "the snapshot is of a VIC-20 with #{setup.ram} RAM, not #{@ram_configuration}"
        end
        return if setup.model == @model

        raise Snapshot::FormatError, "the snapshot is of a #{setup.model.upcase} VIC-20, not a #{@model.upcase} one"
      end
    end

    include KeyedModules
  end
end
