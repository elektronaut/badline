# frozen_string_literal: true

module Badline
  class KIM1
    # The whole machine as keyed snapshot modules (Snapshot::Keyed), in the
    # order a load applies them: BL-MACHINE with the setup, the RAM, U2 and
    # U3, each with its 64 bytes, ports and timer, the panel, the cassette
    # deck, the teletype, the sound's wiring and the CPU.
    module KeyedModules
      def save_modules
        sound = @sound
        [Snapshot::Keyed.section("BL-MACHINE") { |out| save_machine_fields(out) },
         Snapshot::Keyed.section("BL-CPU") { |out| @cpu.save_fields(out) },
         Snapshot::Keyed.section("BL-RAM") { |out| @bus.save_fields(out) },
         Snapshot::Keyed.section("BL-U2") { |out| @u2.save_fields(out) },
         Snapshot::Keyed.section("BL-U3") { |out| @u3.save_fields(out) },
         Snapshot::Keyed.section("BL-PANEL") { |out| @panel.save_fields(out) },
         Snapshot::Keyed.section("BL-DECK") { |out| @panel.tape.save_fields(out) },
         Snapshot::Keyed.section("BL-TTY") { |out| @teletype.save_fields(out) },
         Snapshot::Keyed.section("BL-SOUND") { |out| out.bool("speaker", sound.speaker) }]
      end

      # Raises Snapshot::FormatError for the modules of a machine built
      # another way.
      def load_modules(modules)
        machine = modules.machine
        check_snapshot_setup(Snapshot::KIM1Setup.read_fields(machine))
        load_machine_fields(machine)
        @bus.load_fields(modules.required("BL-RAM"))
        @u2.load_fields(modules.required("BL-U2"))
        @u3.load_fields(modules.required("BL-U3"))
        @panel.load_fields(modules.required("BL-PANEL"))
        @panel.tape.load_fields(modules.required("BL-DECK"))
        @teletype.load_fields(modules.required("BL-TTY"))
        @sound.speaker = modules.required("BL-SOUND").bool("speaker", false)
        @cpu.load_fields(modules.required("BL-CPU"))
        @cpu.restored!
        self
      end

      private

      def check_snapshot_setup(setup)
        ours = Snapshot::KIM1Setup.of(self)
        return if setup == ours

        raise Snapshot::FormatError, "the snapshot is of a #{setup}, not a #{ours}"
      end
    end

    include KeyedModules
  end
end
