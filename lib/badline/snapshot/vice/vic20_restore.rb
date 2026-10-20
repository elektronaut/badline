# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module Vic20
        # Restores a VIC-20 from a snapshot xvic wrote. The modules badline
        # reads become the machine's own keyed modules (Keyed), which it
        # loads as it loads its own snapshot. Whatever they don't set stays
        # as the machine has it at power-on: the VIC-I's sound and picture,
        # which it paints afresh, a cartridge, the datasette's tape, the
        # disk device 8 serves and a true drive, which xvic's drive modules
        # don't reach.
        module Restore
          # MAINCPU and VIC20MEM hold the machine itself, so a version badline
          # doesn't read fails the restore. The others are left out and
          # reported.
          READ = [MainCPU::NAME, Mem::NAME, VICI::NAME, "VIA1", "VIA2"].freeze
          REQUIRED = [MainCPU::NAME, Mem::NAME].freeze

          module_function

          # Applies the modules badline reads to `computer`, and returns a
          # Report. The snapshot goes into a new machine first, so one that
          # fails leaves `computer` as it was, and one of a machine built
          # another way fails too.
          def import(container, computer)
            unless computer.family == :vic20
              raise FormatError, "the snapshot is of a VIC-20, not a #{Image::FAMILIES.fetch(computer.family.to_s)}"
            end

            setup = Vic20.setup(container)
            ours = Vic20Setup.new(ram: computer.ram_configuration, model: computer.model)
            raise FormatError, "the snapshot is of a VIC-20 with #{setup}, not #{ours}" unless setup == ours

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
            READ.each do |name|
              section = container[name]
              next if section.nil?

              if reads?(section)
                applied << name
              else
                raise FormatError, "#{section}: badline doesn't read this version" if REQUIRED.include?(name)

                ignored << "#{section}: badline doesn't read this version, left out"
              end
            end
            REQUIRED.each do |name|
              raise FormatError, "the snapshot has no #{name} module" unless applied.include?(name)
            end
            computer.load_modules(Keyed::Modules.new(modules(container, computer, applied)))
            Report.new(applied:, ignored: ignored + left_out(container, applied))
          end

          def reads?(section)
            case section.name
            when MainCPU::NAME then MainCPU.reads?(section)
            when Mem::NAME then Mem.reads?(section)
            when VICI::NAME then VICI.reads?(section)
            else PET::VIA.reads?(section)
            end
          end

          # The machine's keyed modules: its own as they stand, with those
          # the modules `applied` names stand for in their place.
          def modules(container, computer, applied)
            own = {}
            computer.save_modules.each { |section| own[section.name] = section }
            ram = Keyed::Reader.parse(own.fetch("BL-RAM")).bytes("ram", "".b).bytes
            own["BL-MACHINE"] = Keyed.section("BL-MACHINE") do |out|
              out.text("family", "vic20")
              Vic20Setup.new(ram: computer.ram_configuration, model: computer.model).write_fields(out)
              out.int("cycles", MainCPU.clock(container[MainCPU::NAME]))
              out.bool("nmi_asserted", via_irq?(container, "VIA1", applied))
              Mem.import(container[Mem::NAME], ram, out)
            end
            own["BL-RAM"] = Keyed.section("BL-RAM") { |out| out.bytes("ram", ram) }
            own["BL-CPU"] = Keyed.section("BL-CPU") { |out| MainCPU.import(container[MainCPU::NAME], out) }
            vic(container, computer, applied, own)
            %w[VIA1 VIA2].each do |name|
              next unless applied.include?(name)

              own["BL-#{name}"] = Keyed.section("BL-#{name}") { |out| PET::VIA.import(container[name], out) }
            end
            own.values
          end

          def vic(container, computer, applied, own)
            return unless applied.include?(VICI::NAME)

            section = container[VICI::NAME]
            own["BL-VICI"] = Keyed.section("BL-VICI") { |out| VICI.import(section, out, computer.vic.profile) }
            own["BL-COLORRAM"] = Keyed.section("BL-COLORRAM") { |out| out.bytes("ram", VICI.colors(section)) }
          end

          # Whether the VIA pulls its interrupt line: a flag it has enabled.
          def via_irq?(container, name, applied)
            return false unless applied.include?(name)

            bytes = FieldReader.new(container[name]).bytes(PET::VIA::SIZE)
            bytes[0x12].anybits?(bytes[0x13] & 0x7f)
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
