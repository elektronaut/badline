# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CBM2
        # Restores a CBM-II from a snapshot xcbm2 wrote. The modules badline
        # reads become the machine's own keyed modules (Keyed), which it
        # loads as it loads its own snapshot: the CIA and the SID are read
        # into a machine of their own first, as the C64's are, and saved
        # from there. Whatever they don't set stays as the machine has it
        # at power-on, and the disk device 8 serves through the traps stays
        # as it is.
        module Restore
          # MAINCPU and CBM2MEM hold the machine itself, so a version badline
          # doesn't read fails the restore. The others are left out and
          # reported.
          READ = [MainCPU::NAME, CBM2Mem::NAME, CRTC::NAME, "CIA1", *TPI::NAMES, ACIA::NAME, SIDRegisters::NAME,
                  SIDExtended::NAME].freeze
          REQUIRED = [MainCPU::NAME, CBM2Mem::NAME].freeze
          # TPI1's inputs: the mains on I0, the CIA on I2 and the ACIA on I4.
          MAINS = 0x01
          CIA = 0x04
          ACIA_LINE = 0x10
          # I1, the IEEE-488 bus's SRQ, and I3, the coprocessor's, which
          # nothing pulls.
          IDLE_LINES = 0x0a
          # The modules read into a machine of their own first.
          CHIPS = %w[BL-CIA BL-SID].freeze

          module_function

          # Applies the modules badline reads to `computer`, and returns a
          # Report. The snapshot goes into a new machine first, so one that
          # fails leaves `computer` as it was, and one of a machine built
          # another way fails too.
          def import(container, computer)
            unless computer.family == :cbm2
              raise FormatError, "the snapshot is of a CBM-II, not a #{Image::FAMILIES.fetch(computer.family.to_s)}"
            end

            setup = CBM2.setup(container)
            ours = CBM2Setup.of(computer)
            raise FormatError, "the snapshot is of a #{setup}, not a #{ours}" unless setup == ours

            apply(container, setup.build)
            reapply(computer) { apply(container, computer) }
          end

          # Switches `computer` off and on and applies the snapshot with the
          # block, then reports the disk the traps keep serving and a true
          # drive taken off the bus.
          def reapply(computer)
            had_drive = computer.true_drive
            computer.power_cycle!
            report = yield
            kept = computer.mounted? ? ["the disk mounted in device 8 stays mounted"] : []
            if had_drive && !computer.true_drive.equal?(had_drive)
              kept << "the #{had_drive.model_name} on device #{had_drive.device} is taken off the bus"
            end
            Report.new(applied: report.applied, ignored: report.ignored + kept)
          end

          # Applies the modules badline reads to `computer`, a machine built
          # as the snapshot's was, and returns the Report.
          def apply(container, computer)
            raise FormatError, "the snapshot has no #{MainCPU::NAME} module" if container[MainCPU::NAME].nil?

            applied = []
            ignored = []
            READ.each do |name|
              section = container[name]
              next if section.nil?

              reason = refusal(section, container)
              if reason.nil?
                applied << name
              else
                raise FormatError, "#{section}: #{reason}" if REQUIRED.include?(name)

                ignored << "#{section}: #{reason}, left out"
              end
            end
            computer.load_modules(Keyed::Modules.new(modules(container, computer, applied, ignored)))
            Report.new(applied:, ignored: ignored + left_out(container, applied))
          end

          # Why badline leaves the module out, or nil when it reads it.
          def refusal(section, container)
            return "badline doesn't read this version" unless reads?(section)

            "another SID engine wrote it" if section.name == SIDExtended::NAME && !Vice::Restore.resid?(container)
          end

          def reads?(section)
            case section.name
            when MainCPU::NAME then PET::MainCPU.reads?(section)
            when CBM2Mem::NAME then CBM2Mem.reads?(section)
            when CRTC::NAME then CRTC.reads?(section)
            when "CIA1" then CIAs.reads?(section)
            when ACIA::NAME then ACIA.reads?(section)
            when SIDRegisters::NAME then SIDRegisters.reads?(section)
            when SIDExtended::NAME then SIDExtended.reads?(section)
            else TPI.reads?(section)
            end
          end

          # The machine's keyed modules: its own at power-on, with those the
          # modules `applied` names stand for in their place.
          def modules(container, computer, applied, ignored)
            chips = chips(container, computer, applied)
            own = {}
            computer.save_modules.each { |section| own[section.name] = section }
            drive(container, computer, applied, ignored, own)
            chips.save_modules.each { |section| own[section.name] = section if CHIPS.include?(section.name) }
            cycles = FieldReader.new(container[MainCPU::NAME]).qword
            crtc = crtc(container, computer, applied, own)
            high = machine(own, computer, cycles, crtc)
            own["BL-RAM"] = Keyed.section("BL-RAM") do |out|
              CBM2Mem.import(container[CBM2Mem::NAME], out, computer.model.ram_segments)
            end
            own["BL-CPU"] = Keyed.section("BL-CPU") { |out| PET::MainCPU.import(container[MainCPU::NAME], out) }
            if applied.include?(ACIA::NAME)
              own["BL-ACIA"] = Keyed.section("BL-ACIA") { |out| ACIA.import(container[ACIA::NAME], out, cycles) }
            end
            lines = IDLE_LINES | (high ? MAINS : 0) | (chips.cia.interrupted? ? 0 : CIA)
            tpis(container, applied, own, acia_irq?(container, applied) ? lines : lines | ACIA_LINE)
            own.values
          end

          # Puts the true drive's modules in `own` in place of badline's: the
          # 2031, 8050 or 8250 the snapshot has, as xpet's are read
          # (PET::Restore), with the disks badline's drive of that model has,
          # or none.
          def drive(container, computer, applied, ignored, own)
            disks = PET::Restore::DISKS.filter_map { |name| own[name] }
            own.delete_if { |name, _| name.match?(/\ABL-D\d+(-|\z)/) }
            kept = PET::Restore.kept_disks(container, computer, disks)
            PET::Restore.drive(container, applied, ignored, kept).each { |section| own[section.name] = section }
          end

          # A machine of its own with xcbm2's CIA and SID read into it.
          def chips(container, computer, applied)
            machine = CBM2Setup.of(computer).build
            CIAs.import_into(container["CIA1"], machine.cia) if applied.include?("CIA1")
            SIDRegisters.import(container[SIDRegisters::NAME], machine) if applied.include?(SIDRegisters::NAME)
            SIDExtended.import(container[SIDExtended::NAME], machine) if applied.include?(SIDExtended::NAME)
            machine
          end

          # Puts the CRTC's and the picture's modules in `own`, and returns
          # the CRTC's fields.
          def crtc(container, computer, applied, own)
            return Keyed::Reader.parse(own.fetch("BL-CRTC")) unless applied.include?(CRTC::NAME)

            section = CRTC.import(container[CRTC::NAME], computer)
            fields = Keyed::Reader.parse(section)
            own["BL-CRTC"] = section
            own["BL-VIDEO"] = CRTC.video(container[CRTC::NAME], fields)
            fields
          end

          # Puts BL-MACHINE in `own`, with the mains' next falling edge where
          # xcbm2 ticks it for the CRTC's fields `crtc`, and returns whether
          # the mains is high.
          def machine(own, computer, cycles, crtc)
            high = true
            own["BL-MACHINE"] = Keyed.section("BL-MACHINE") do |out|
              out.text("family", "cbm2")
              CBM2Setup.of(computer).write_fields(out)
              out.int("cycles", cycles)
              high = Mains.write(out, Mains.next_tick(crtc), Badline::CBM2::CLOCK_HZ / (2 * computer.mains_hz))
            end
            high
          end

          # Puts both TPIs' modules in `own`, TPI1's with its interrupt
          # inputs at `lines`, TPI2's all high.
          def tpis(container, applied, own, lines)
            TPI::NAMES.zip([lines, 0x1f]).each do |name, levels|
              next unless applied.include?(name)

              own["BL-#{name}"] = Keyed.section("BL-#{name}") { |out| TPI.import(container[name], out, levels) }
            end
          end

          # Whether the ACIA pulls its IRQ line: its status has the
          # interrupt, and DTR enables it.
          def acia_irq?(container, applied)
            return false unless applied.include?(ACIA::NAME)

            fields = FieldReader.new(container[ACIA::NAME]).skip(2)
            fields.byte.anybits?(ACIA::IRQ) && fields.byte.anybits?(0x01)
          end

          def left_out(container, applied)
            container.sections.reject { |section| applied.include?(section.name) }
                     .map { |section| "#{section}: badline doesn't read this module, left out" }
          end
        end
      end
    end
  end
end
