# frozen_string_literal: true

module Badline
  class C64
    # The whole machine as keyed snapshot modules (Snapshot::Keyed), in the
    # order a load applies them: BL-MACHINE with the setup, the memories,
    # the cartridge, the CPU with its port, the chips with any extra SIDs
    # (Bus::ExtraSIDs), an REU, the datasette, device 8 through the traps
    # and the true drives. A load
    # reads the CPU's port before the chips, so the banks are mapped as the
    # chips load, and the CPU's own fields after them. What each unit works
    # out again from its fields comes last, once every unit is loaded.
    module KeyedModules
      def save_modules
        bus = address_bus
        sections = [Snapshot::Keyed.section("BL-MACHINE") { |out| save_machine_fields(out) },
                    Snapshot::Keyed.section("BL-RAM") { |out| bus.ram.save_fields(out, "ram") }]
        expansion = bus.ram_expansion
        sections << Snapshot::Keyed.section("BL-RAMEXP") { |out| expansion.save_fields(out) } if expansion.type
        sections << Snapshot::Keyed.section("BL-COLORRAM") { |out| bus.color_ram.save_fields(out, "ram") }
        cartridge = bus.cartridge
        sections << Snapshot::Keyed.section("BL-CART") { |out| cartridge.save_fields(out) } if cartridge
        save_chip_modules(sections, bus)
        reu = @reu
        sections << Snapshot::Keyed.section("BL-REU") { |out| reu.save_fields(out) } if reu
        sections << Snapshot::Keyed.section("BL-TAPE") { |out| bus.datasette.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TRAPDOS") { |out| save_trap_dos_fields(out) } if mounted?
        save_drive_modules(sections)
      end

      # Raises Snapshot::FormatError for the modules of a machine built
      # another way.
      def load_modules(modules)
        machine = modules.machine
        check_snapshot_setup(Snapshot::C64Setup.read_fields(machine))
        load_machine_fields(machine)
        bus = address_bus
        bus.ram.load_fields(modules.required("BL-RAM"), "ram")
        bus.ram_expansion.load_fields(modules.required("BL-RAMEXP")) if bus.ram_expansion.type
        bus.color_ram.load_fields(modules.required("BL-COLORRAM"), "ram")
        load_cartridge_module(modules.optional("BL-CART"))
        cpu = modules.required("BL-CPU")
        bus.load_port_fields(cpu)
        bus.restored!
        load_chip_modules(modules, cpu)
        bus.datasette.load_fields(modules.required("BL-TAPE"))
        load_trap_dos_module(modules)
        load_drive_modules(modules)
        modules_restored!
        self
      end

      private

      def save_chip_modules(sections, bus)
        sections << Snapshot::Keyed.section("BL-CPU") do |out|
          @cpu.save_fields(out)
          bus.save_port_fields(out)
        end
        sections << Snapshot::Keyed.section("BL-VIC") { |out| @vic.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-CIA1") { |out| @cia1.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-CIA2") { |out| @cia2.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-SID") { |out| @sid.save_fields(out) }
        bus.save_extra_sid_modules(sections)
      end

      def load_chip_modules(modules, cpu)
        @vic.load_fields(modules.required("BL-VIC"))
        @cia1.load_fields(modules.required("BL-CIA1"))
        @cia2.load_fields(modules.required("BL-CIA2"))
        @sid.load_fields(modules.required("BL-SID"))
        address_bus.load_extra_sid_modules(modules)
        @reu&.load_fields(modules.required("BL-REU"))
        @cpu.load_fields(cpu)
      end

      # The cartridge comes back built afresh from the CRT image the module
      # holds, before its state goes in. No module means no cartridge.
      def load_cartridge_module(input)
        if input
          cartridge = Cartridge.from_fields(input)
          connect_cartridge(cartridge)
          cartridge.load_fields(input)
        elsif address_bus.cartridge
          address_bus.detach_cartridge
        end
      end

      def load_trap_dos_module(modules)
        input = modules.optional("BL-TRAPDOS")
        input ? load_trap_dos_fields(input, detached: modules.detached?) : unmount
      end

      def modules_restored!
        @cpu.restored!
        @vic.restored!
        @cia1.restored!
        @cia2.restored!
        @sid.restored!
        address_bus.extra_sids.each(&:restored!)
        @reu&.restored!
        machine_restored!
      end

      def check_snapshot_setup(setup)
        ours = Snapshot::C64Setup.of(address_bus)
        return if setup == ours

        raise Snapshot::FormatError, "the snapshot is of a machine with #{setup}, not #{ours}"
      end
    end

    include KeyedModules
  end
end
