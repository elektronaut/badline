# frozen_string_literal: true

module Badline
  class C128
    # The whole machine as keyed snapshot modules (Snapshot::Keyed), in the
    # order a load applies them, as C64::KeyedModules: BL-MACHINE with the
    # last bus access under bus.*, the RAM, both banks of colour RAM, the
    # MMU, the cartridge, the 8502 with its port, the Z80, the chips, the
    # datasette, device 8 through the traps and the true drives. The
    # machine's own fields load after the Z80's, which z80_ahead counts
    # from.
    module KeyedModules
      def save_modules
        bus = @bus
        sections = [Snapshot::Keyed.section("BL-MACHINE") do |out|
          save_machine_fields(out)
          bus.save_fields(out, "bus.")
        end]
        sections << Snapshot::Keyed.section("BL-RAM") { |out| bus.ram.save_fields(out, "ram") }
        sections << Snapshot::Keyed.section("BL-COLORRAM") { |out| bus.save_color_fields(out) }
        sections << Snapshot::Keyed.section("BL-MMU") { |out| bus.mmu.save_fields(out) }
        cartridge = bus.cartridge
        sections << Snapshot::Keyed.section("BL-CART") { |out| cartridge.save_fields(out) } if cartridge
        save_chip_modules(sections, bus)
        sections << Snapshot::Keyed.section("BL-TAPE") { |out| bus.datasette.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TRAPDOS") { |out| save_trap_dos_fields(out) } if mounted?
        save_drive_modules(sections)
      end

      # Raises Snapshot::FormatError for the modules of another model, SID
      # or mode.
      def load_modules(modules)
        machine = modules.machine
        check_snapshot_setup(Snapshot::C128Setup.read_fields(machine))
        bus = @bus
        bus.ram.load_fields(modules.required("BL-RAM"), "ram")
        bus.load_color_fields(modules.required("BL-COLORRAM"))
        bus.mmu.load_fields(modules.required("BL-MMU"))
        load_cartridge_module(modules.optional("BL-CART"))
        load_chip_modules(modules)
        bus.load_fields(machine, "bus.")
        load_machine_fields(machine)
        bus.datasette.load_fields(modules.required("BL-TAPE"))
        trap_dos = modules.optional("BL-TRAPDOS")
        trap_dos ? load_trap_dos_fields(trap_dos, detached: modules.detached?) : unmount
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
        sections << Snapshot::Keyed.section("BL-Z80") { |out| @z80.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-VIC") { |out| @vic.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-VDC") { |out| @vdc.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-CIA1") { |out| @cia1.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-CIA2") { |out| @cia2.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-SID") { |out| @sid.save_fields(out) }
      end

      # The port goes in ahead of the chips, as the C64's does, and the bus
      # maps its banks and the keyboard's extra rows once they are in. That
      # hands the bus to the CPU the MMU names, which resets the Z80's
      # schedule and can reset the 8502, so the CPUs, the last bus access
      # and the machine's own fields load after it.
      def load_chip_modules(modules)
        cpu = modules.required("BL-CPU")
        @bus.load_port_fields(cpu)
        @vic.load_fields(modules.required("BL-VIC"))
        @vdc.load_fields(modules.required("BL-VDC"))
        @cia1.load_fields(modules.required("BL-CIA1"))
        @cia2.load_fields(modules.required("BL-CIA2"))
        @sid.load_fields(modules.required("BL-SID"))
        @bus.restored!
        @cpu.load_fields(cpu)
        @z80.load_fields(modules.required("BL-Z80"))
      end

      # The cartridge comes back built afresh from the CRT image the module
      # holds, before its state goes in. No module means no cartridge.
      def load_cartridge_module(input)
        if input
          cartridge = C64::Cartridge.from_fields(input)
          connect_cartridge(cartridge)
          cartridge.load_fields(input)
        elsif @bus.cartridge
          @bus.detach_cartridge
        end
      end

      def modules_restored!
        @cpu.restored!
        @z80.restored!
        @vic.restored!
        @vdc.restored!
        @cia1.restored!
        @cia2.restored!
        @sid.restored!
        machine_restored!
      end

      def check_snapshot_setup(setup)
        ours = snapshot_setup
        return if setup == ours

        raise Snapshot::FormatError, "the snapshot is of a #{setup}, not a #{ours}"
      end
    end

    include KeyedModules
  end
end
