# frozen_string_literal: true

module Badline
  class CBM2
    class P500
      # The machine's own fields as the B series keeps them (CBM2::KeyedState),
      # and the whole machine as keyed snapshot modules (Snapshot::Keyed), in
      # the order a load applies them: BL-MACHINE with the setup, the RAM
      # with the segment registers, the colour RAM, the VIC, the SID, the
      # CIA, the ACIA, both TPIs, the CPU, device 8 through the traps and a
      # true 2031 on the IEEE-488 bus.
      #
      # A load lays the pages out before the chips load, and works out what
      # each unit derives from its fields, the VIC's view of memory among
      # them, once every unit is loaded.
      module KeyedModules
        # The SID's deferred cycles and writes, run up to this cycle, and the
        # VIC's sprite collisions latched up to the beam.
        def settle_chips_for_snapshot
          @sid.catch_up!
          @vic.fold_collisions!
        end

        def save_modules
          bus = @bus
          sections = [Snapshot::Keyed.section("BL-MACHINE") { |out| save_machine_fields(out) }]
          sections << Snapshot::Keyed.section("BL-CPU") { |out| @cpu.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-RAM") { |out| bus.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-COLORRAM") { |out| @color_ram.save_fields(out, "ram") }
          sections << Snapshot::Keyed.section("BL-VIC") { |out| @vic.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-SID") { |out| @sid.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-CIA") { |out| @cia.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-ACIA") { |out| @acia.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-TPI1") { |out| @tpi1.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-TPI2") { |out| @tpi2.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-TRAPDOS") { |out| save_trap_dos_fields(out) } if mounted?
          save_drive_modules(sections)
        end

        # Raises Snapshot::FormatError for the modules of a machine built
        # another way.
        def load_modules(modules)
          check_snapshot_setup(Snapshot::CBM2Setup.read_fields(modules.machine))
          load_machine_fields(modules.machine)
          @bus.load_fields(modules.required("BL-RAM"))
          @bus.restored!
          @color_ram.load_fields(modules.required("BL-COLORRAM"), "ram")
          @vic.load_fields(modules.required("BL-VIC"))
          @sid.load_fields(modules.required("BL-SID"))
          @cia.load_fields(modules.required("BL-CIA"))
          @acia.load_fields(modules.required("BL-ACIA"))
          @tpi1.load_fields(modules.required("BL-TPI1"))
          @tpi2.load_fields(modules.required("BL-TPI2"))
          @cpu.load_fields(modules.required("BL-CPU"))
          trap_dos = modules.optional("BL-TRAPDOS")
          trap_dos ? load_trap_dos_fields(trap_dos, detached: modules.detached?) : unmount
          load_drive_modules(modules)
          restored!
          self
        end

        private

        def restored!
          @cpu.restored!
          @vic.restored!
          @sid.restored!
          @cia.restored!
          @acia.restored!
          update_video_bus
        end

        def check_snapshot_setup(setup)
          ours = Snapshot::CBM2Setup.of(self)
          return if setup == ours

          raise Snapshot::FormatError, "the snapshot is of a #{setup}, not a #{ours}"
        end
      end

      include CBM2::KeyedState
      include KeyedModules
    end
  end
end
