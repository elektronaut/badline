# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # Restores a PET from a snapshot xpet wrote. The modules badline
        # reads become the PET's own keyed modules (Keyed), which it loads
        # as it loads its own snapshot. Whatever they don't set stays as the
        # machine has it at power-on, and the datasettes' tapes and the
        # disk device 8 serves stay as they are. A snapshot with a true 2031,
        # 8050 or 8250 puts one on the bus, with the disks badline's drive
        # of that model had in it, and one without takes badline's off.
        module Restore
          # MAINCPU and PETMEM hold the machine itself, so a version badline
          # doesn't read fails the restore. The others are left out and
          # reported.
          READ = [MainCPU::NAME, PETMem::NAME, CRTC::NAME, "PIA1", "PIA2", VIA::NAME].freeze
          # The SuperPET's too: its 6809 and its ACIA. A SuperPET's board
          # comes from PETMEM.
          SUPERPET_READ = [CPU6809::NAME, CBM2::ACIA::NAME].freeze
          # The host's media, which a restore keeps.
          KEPT = %w[BL-TAPE1 BL-TAPE2 BL-TRAPDOS].freeze
          # The disks in a true drive's drives, which a restore keeps.
          DISKS = %w[BL-D8-DISK BL-D8-DISK1].freeze

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
            had_drive = computer.true_drive
            computer.power_cycle!
            report = apply(container, computer)
            kept = computer.mounted? ? ["the disk mounted in device 8 stays mounted"] : []
            if had_drive && !computer.true_drive.equal?(had_drive)
              kept << "the #{had_drive.model_name} on device #{had_drive.device} is taken off the bus"
            end
            Report.new(applied: report.applied, ignored: report.ignored + kept)
          end

          # Applies the modules badline reads to `computer`, a machine built
          # as the snapshot's was, and returns the Report.
          def apply(container, computer)
            applied = []
            ignored = []
            sections = []
            names = read_names(computer)
            names.each do |name|
              section = container[name]
              next if section.nil?

              if reads?(section)
                applied << name
              else
                raise FormatError, "#{section}: badline doesn't read this version" if required?(name)

                ignored << "#{section}: badline doesn't read this version, left out"
              end
            end
            disks = []
            computer.save_modules.each do |section|
              sections << section if KEPT.include?(section.name)
              disks << section if DISKS.include?(section.name)
            end
            sections += drive(container, applied, ignored, kept_disks(container, computer, disks))
            computer.load_modules(Keyed::Modules.new(modules(container, computer, applied) + sections))
            Report.new(applied:, ignored: ignored + left_out(container, names, applied))
          end

          def read_names(computer) = computer.superpet? ? READ + SUPERPET_READ : READ

          # The disks badline's true drive has, which stay in the drive the
          # snapshot puts on the bus when it is of the same model.
          def kept_disks(container, computer, disks)
            drive = computer.true_drive
            return [] if drive.nil?

            if Drive8050.present?(container)
              Drive8050.model(container) == drive.model_name ? disks : []
            else
              drive.model_name == "2031" ? disks.first(1) : []
            end
          end

          # The true drive's modules where the snapshot has one badline
          # reads, or none.
          def drive(container, applied, ignored, disks)
            return drive8050(container, applied, ignored, disks) if Drive8050.present?(container)
            return [] unless Drive2031.present?(container)

            names = [Drive2031::UNITS.first, Drive2031::CPU, Drive2031::VIA1, Drive2031::VIA2]
            return [] unless readable?(container, names, "2031", ignored) { |section| Drive2031.reads?(section) }

            applied.concat(names)
            Drive2031.import(container, disks.first)
          end

          def drive8050(container, applied, ignored, disks)
            model = Drive8050.model(container)
            return [] unless readable?(container, Drive8050::NAMES, model || "8050", ignored) do |section|
              Drive8050.reads?(section)
            end

            if model.nil?
              ignored << "the true drive: badline doesn't read its #{Drive8050::UNIT}'s type, left out"
              return []
            end

            applied.concat(Drive8050::NAMES)
            Drive8050.import(container, Drive8050.reference(model), disks)
          end

          # Whether the snapshot has every module `names` lists at a version
          # badline reads, saying which it doesn't in `ignored`.
          def readable?(container, names, model, ignored, &reads)
            unread = names.map { |name| container[name] }.reject { |section| section && reads.call(section) }
            return true if unread.empty?

            ignored << "the true #{model}: badline doesn't read #{unread.compact.join(', ')}, left out"
            false
          end

          def required?(name) = [MainCPU::NAME, PETMem::NAME].include?(name)

          def reads?(section)
            case section.name
            when MainCPU::NAME then MainCPU.reads?(section)
            when PETMem::NAME then PETMem.reads?(section)
            when CRTC::NAME then CRTC.reads?(section)
            when VIA::NAME then VIA.reads?(section)
            when CPU6809::NAME then CPU6809.reads?(section)
            when CBM2::ACIA::NAME then CBM2::ACIA.reads?(section)
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
            sections += superpet(container, applied) if computer.superpet?
            sections + video
          end

          # The SuperPET's board, and its 6809 while it has the bus and its
          # ACIA where the snapshot has them. The 6809 the 6502 has the bus
          # from, and a module left out, stay as the machine has them at
          # power-on.
          def superpet(container, applied)
            cycles = FieldReader.new(container[MainCPU::NAME]).qword
            memory = container[PETMem::NAME]
            sections = [Keyed.section("BL-SUPERPET") { |out| PETMem.import_superpet(memory, out) }]
            if applied.include?(CPU6809::NAME) && PETMem.m6809?(memory)
              sections << Keyed.section("BL-M6809") { |out| CPU6809.import(container[CPU6809::NAME], out, cycles) }
            end
            return sections unless applied.include?(CBM2::ACIA::NAME)

            sections << Keyed.section("BL-ACIA") { |out| CBM2::ACIA.import(container[CBM2::ACIA::NAME], out, cycles) }
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
          # cycle xpet's does (CRTC::CRTC_LEAD). The CRTC runs on from the
          # start of the beam's line, or for a beam in the first cycles of
          # its line, a frame less those cycles on, which lands on the same
          # counters while the registers stood through the frame as they
          # stand.
          def video(crtc, computer)
            return [] if crtc.nil?

            model = computer.model
            return [Keyed.section("BL-VIDEO") { |out| CRTC.import_discrete(crtc, out) }] if model.video == :discrete

            counters = Keyed.section("BL-CRTC") do |out|
              CRTC.import(crtc, out, CRTC.columns(model), CRTC.attributes(model))
            end
            cycles = (CRTC::CRTC_LEAD + CRTC.column_of(crtc)) % CRTC.frame_cycles(CRTC.registers(crtc))
            fields = CRTC.run_on(CRTC.fresh_crtc(computer), Keyed::Reader.parse(counters), cycles)
            [Keyed.section("BL-CRTC") { |out| CRTC.copy(fields, out) }]
          end

          def left_out(container, names, applied)
            container.sections.reject { |section| names.include?(section.name) || applied.include?(section.name) }
                     .map { |section| "#{section}: badline doesn't read this module, left out" }
          end
        end
      end
    end
  end
end
