# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # Restores a PET from a snapshot xpet wrote. The modules badline
        # reads become the PET's own keyed modules (Keyed), which it loads
        # as it loads its own snapshot. Whatever they don't set stays as the
        # machine has it at power-on, and the datasettes' tapes and the
        # disk device 8 serves stay as they are.
        module Restore
          # MAINCPU and PETMEM hold the machine itself, so a version badline
          # doesn't read fails the restore. The others are left out and
          # reported.
          READ = [MainCPU::NAME, PETMem::NAME, CRTC::NAME, "PIA1", "PIA2", VIA::NAME].freeze
          # The host's media, which a restore keeps.
          KEPT = %w[BL-TAPE1 BL-TAPE2 BL-TRAPDOS].freeze

          module_function

          # Applies the modules badline reads to `computer`, and returns a
          # Report. The snapshot goes into a new machine first, so one that
          # fails leaves `computer` as it was, and one of a machine built
          # another way fails too.
          def import(container, computer)
            unless computer.family == :pet
              raise FormatError, "the snapshot is of a PET, not a #{Image::FAMILIES.fetch(computer.family.to_s)}"
            end

            setup = PET.setup(container)
            ours = PETSetup.of(computer)
            raise FormatError, "the snapshot is of a #{setup}, not a #{ours}" unless setup == ours

            apply(container, setup.build)
            computer.power_cycle!
            report = apply(container, computer)
            kept = computer.mounted? ? ["the disk mounted in device 8 stays mounted"] : []
            Report.new(applied: report.applied, ignored: report.ignored + kept)
          end

          # Applies the modules badline reads to `computer`, a machine built
          # as the snapshot's was, and returns the Report.
          def apply(container, computer)
            applied = []
            ignored = []
            sections = []
            READ.each do |name|
              section = container[name]
              next if section.nil?

              if reads?(section)
                applied << name
              else
                raise FormatError, "#{section}: badline doesn't read this version" if required?(name)

                ignored << "#{section}: badline doesn't read this version, left out"
              end
            end
            computer.save_modules.each { |section| sections << section if KEPT.include?(section.name) }
            computer.load_modules(Keyed::Modules.new(modules(container, computer, applied) + sections))
            Report.new(applied:, ignored: ignored + left_out(container))
          end

          def required?(name) = [MainCPU::NAME, PETMem::NAME].include?(name)

          def reads?(section)
            case section.name
            when MainCPU::NAME then MainCPU.reads?(section)
            when PETMem::NAME then PETMem.reads?(section)
            when CRTC::NAME then CRTC.reads?(section)
            when VIA::NAME then VIA.reads?(section)
            else PIAs.reads?(section)
            end
          end

          # The PET's keyed modules from the ones `applied` names.
          def modules(container, computer, applied)
            model = computer.model
            crtc = applied.include?(CRTC::NAME) ? container[CRTC::NAME] : nil
            video = video(crtc, computer)
            drive = driving?(crtc, video, model)
            sections = [Keyed.section("BL-MACHINE") { |out| machine(out, container, computer, drive) },
                        Keyed.section("BL-RAM") do |out|
                          PETMem.import(container[PETMem::NAME], out, model.screen_bytes)
                        end]
            sections << Keyed.section("BL-CPU") { |out| MainCPU.import(container[MainCPU::NAME], out) }
            %w[PIA1 PIA2].each do |name|
              next unless applied.include?(name)

              sections << Keyed.section("BL-#{name}") do |out|
                PIAs.import(container[name], out)
                out.bool("cb.c1_high", drive) if name == "PIA1"
              end
            end
            if applied.include?(VIA::NAME)
              sections << Keyed.section("BL-VIA") { |out| VIA.import(container[VIA::NAME], out) }
            end
            sections + video
          end

          def machine(out, container, computer, drive)
            out.text("family", "pet")
            PETSetup.of(computer).write_fields(out)
            out.int("cycles", FieldReader.new(container[MainCPU::NAME]).qword).bool("vertical_drive", drive)
          end

          # The vertical drive line, low in the CRTC's vertical sync or past
          # the discrete video's rows, as the video's module, `video`, has it.
          def driving?(crtc, video, model)
            return true if crtc.nil?

            fields = Keyed::Reader.parse(video.first)
            if model.video == :discrete
              fields.int("line", 0) < Badline::PET::DiscreteVideo::DISPLAYED_LINES
            else
              fields.int("vsync_lines", 0).zero?
            end
          end

          # The discrete video's module, or the CRTC's, run on from xpet's
          # counters to where badline's drops the vertical drive line on the
          # cycle xpet's does (CRTC::CRTC_LEAD).
          def video(crtc, computer)
            return [] if crtc.nil?

            model = computer.model
            return [Keyed.section("BL-VIDEO") { |out| CRTC.import_discrete(crtc, out) }] if model.video == :discrete

            counters = Keyed.section("BL-CRTC") do |out|
              CRTC.import(crtc, out, CRTC.columns(model), CRTC.attributes(model))
            end
            cycles = (CRTC::CRTC_LEAD + CRTC.column_of(crtc)) % CRTC.frame_cycles(CRTC.registers(crtc))
            fields = CRTC.run_on(computer, Keyed::Reader.parse(counters), cycles)
            [Keyed.section("BL-CRTC") { |out| CRTC.copy(fields, out) }]
          end

          def left_out(container)
            container.sections.reject { |section| READ.include?(section.name) }
                     .map { |section| "#{section}: badline doesn't read this module, left out" }
          end
        end
      end
    end
  end
end
