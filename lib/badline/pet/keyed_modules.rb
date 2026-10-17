# frozen_string_literal: true

module Badline
  class PET
    # The whole machine as keyed snapshot modules (Snapshot::Keyed), in the
    # order a load applies them: BL-MACHINE with the setup, the RAM with
    # the screen RAM, the last byte on the bus and an 8096's board, both
    # PIAs, the VIA, the CRTC where the model has one, the picture with
    # the video's beam, the CPU, the datasettes at cassette ports #1 and
    # #2, and device 8 through the traps.
    #
    # A load lays the pages out before the chips load, and works out what
    # each unit derives from its fields once every unit is loaded.
    module KeyedModules
      def save_modules
        bus = @bus
        sections = [Snapshot::Keyed.section("BL-MACHINE") { |out| save_machine_fields(out) }]
        sections << Snapshot::Keyed.section("BL-CPU") { |out| @cpu.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-RAM") { |out| bus.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-PIA1") { |out| @pia1.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-PIA2") { |out| @pia2.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-VIA") { |out| @via.save_fields(out) }
        save_video_modules(sections)
        cassettes = @cassettes
        sections << Snapshot::Keyed.section("BL-TAPE1") { |out| cassettes.datasette1.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TAPE2") { |out| cassettes.datasette2.save_fields(out) }
        sections << Snapshot::Keyed.section("BL-TRAPDOS") { |out| save_trap_dos_fields(out) } if mounted?
        sections
      end

      # Raises Snapshot::FormatError for the modules of a machine built
      # another way.
      def load_modules(modules)
        machine = modules.machine
        check_snapshot_setup(Snapshot::PETSetup.read_fields(machine))
        load_machine_fields(machine)
        @bus.load_fields(modules.required("BL-RAM"))
        @bus.restored!
        @pia1.load_fields(modules.required("BL-PIA1"))
        @pia2.load_fields(modules.required("BL-PIA2"))
        @via.load_fields(modules.required("BL-VIA"))
        load_video_modules(modules)
        @cpu.load_fields(modules.required("BL-CPU"))
        @cassettes.datasette1.load_fields(modules.required("BL-TAPE1"))
        @cassettes.datasette2.load_fields(modules.required("BL-TAPE2"))
        trap_dos = modules.optional("BL-TRAPDOS")
        trap_dos ? load_trap_dos_fields(trap_dos, detached: modules.detached?) : unmount
        @cpu.restored!
        @via.restored!
        self
      end

      private

      # The CRTC and what the CRTC boards paint from it, or what the
      # discrete boards paint.
      def save_video_modules(sections)
        if @crtc_video
          sections << Snapshot::Keyed.section("BL-CRTC") { |out| @crtc.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-VIDEO") { |out| @crtc_output.save_fields(out) }
        else
          sections << Snapshot::Keyed.section("BL-VIDEO") { |out| @discrete.save_fields(out) }
        end
      end

      def load_video_modules(modules)
        if @crtc_video
          @crtc.load_fields(modules.required("BL-CRTC"))
          @crtc_output.load_fields(modules.required("BL-VIDEO"))
        else
          @discrete.load_fields(modules.required("BL-VIDEO"))
        end
      end

      def check_snapshot_setup(setup)
        ours = Snapshot::PETSetup.of(self)
        return if setup == ours

        raise Snapshot::FormatError, "the snapshot is of a #{setup}, not a #{ours}"
      end
    end

    include KeyedModules
  end
end
