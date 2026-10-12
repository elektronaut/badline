# frozen_string_literal: true

module Badline
  class Plus4
    # The whole machine as keyed snapshot modules (Snapshot::Keyed): BL-MACHINE
    # with the setup, the cartridges' ROMs by slot, the CPU with its port,
    # the TED, its sound, the keyboard's 6529, the user port's 6529 and the
    # ACIA where the model has them, the TCBM interface's TIAs where one is
    # plugged in, the RAM with the ROM bank latch and the ROM/RAM switch
    # under bus.*, the datasette, device 8 through the traps and the true
    # drives.
    #
    # A load maps the banks before the chips load, and works out what each
    # unit derives from its fields once every unit is loaded.
    module KeyedModules
      def save_modules
        bus = @bus
        sections = [Snapshot::Keyed.section("BL-MACHINE") { |out| save_machine_fields(out) }]
        sections << Snapshot::Keyed.section("BL-CART") { |out| bus.save_slot_fields(out) } if bus.cartridge?
        save_chip_modules(sections)
        sections << Snapshot::Keyed.section("BL-RAM") do |out|
          bus.ram.save_fields(out, "ram")
          bus.save_fields(out, "bus.")
        end
        sections << Snapshot::Keyed.section("BL-TAPE") { |out| @datasette.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TRAPDOS") { |out| save_trap_dos_fields(out) } if mounted?
        save_drive_modules(sections)
      end

      # Raises Snapshot::FormatError for the modules of a machine built
      # another way.
      def load_modules(modules)
        machine = modules.machine
        check_snapshot_setup(Snapshot::Plus4Setup.read_fields(machine))
        load_machine_fields(machine)
        bus = @bus
        memory = modules.required("BL-RAM")
        bus.ram.load_fields(memory, "ram")
        bus.load_fields(memory, "bus.")
        bus.load_slot_fields(modules.optional("BL-CART") || Snapshot::Keyed::Reader.new("BL-CART"))
        bus.restored!
        load_chip_modules(modules)
        @datasette.load_fields(modules.required("BL-TAPE"))
        trap_dos = modules.optional("BL-TRAPDOS")
        trap_dos ? load_trap_dos_fields(trap_dos, detached: modules.detached?) : unmount
        load_drive_modules(modules)
        modules_restored!
        self
      end

      private

      def save_chip_modules(sections)
        sections << Snapshot::Keyed.section("BL-CPU") do |out|
          @cpu.save_fields(out)
          @port.save_fields(out, "port.")
        end
        sections << Snapshot::Keyed.section("BL-TED") { |out| @ted.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TEDSOUND") { |out| @sound.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-KEYPORT") { |out| @keyboard_port.save_fields(out) }
        user_port = @user_port
        sections << Snapshot::Keyed.section("BL-USERPORT") { |out| user_port.save_fields(out) } if user_port
        acia = @acia
        sections << Snapshot::Keyed.section("BL-ACIA") { |out| acia.save_fields(out) } if acia
        @tias.each_with_index do |tia, index|
          sections << Snapshot::Keyed.section("BL-TIA#{index + 1}") { |out| tia.save_fields(out) }
        end
      end

      def load_chip_modules(modules)
        cpu = modules.required("BL-CPU")
        @port.load_fields(cpu, "port.")
        @ted.load_fields(modules.required("BL-TED"))
        @sound.load_fields(modules.required("BL-TEDSOUND"))
        @keyboard_port.load_fields(modules.required("BL-KEYPORT"))
        @user_port&.load_fields(modules.required("BL-USERPORT"))
        @acia&.load_fields(modules.required("BL-ACIA"))
        @tias.each_with_index { |tia, index| tia.load_fields(modules.required("BL-TIA#{index + 1}")) }
        @cpu.load_fields(cpu)
      end

      def modules_restored!
        @cpu.restored!
        @ted.restored!
        @sound.restored!(@ted)
        @port.restored!
      end

      def check_snapshot_setup(setup)
        ours = Snapshot::Plus4Setup.of(self)
        return if setup == ours

        raise Snapshot::FormatError, "the snapshot is of a #{setup}, not a #{ours}"
      end
    end

    include KeyedModules
  end
end
