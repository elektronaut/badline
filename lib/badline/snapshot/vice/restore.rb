# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # Restores a machine from a snapshot VICE wrote, through the modules
      # badline reads.
      module Restore
        # The modules badline reads, in the order it applies them: the VIC
        # comes last, as it is clocked to its cycle through memory and CIA 2.
        # MAINCPU and C64MEM hold the machine itself, so a version badline
        # doesn't read fails the restore; the others are left out and
        # reported.
        READ = [MainCPU::NAME, C64Mem::NAME, "CIA1", "CIA2", SIDRegisters::NAME, SIDExtended::NAME,
                VICII::NAME].freeze
        REQUIRED = [MainCPU::NAME, C64Mem::NAME].freeze

        module_function

        # Applies the modules badline reads to `computer`, and returns a
        # Report naming what it applied and, with a reason, what it left out.
        # The snapshot goes into a new machine first, so one that fails leaves
        # `computer` as it was, and one of a machine built another way fails
        # too. Then the machine is taken to power-on with its cartridge out,
        # so nothing it was doing carries into the snapshot's machine.
        def import(container, computer)
          setup = Vice.setup(container)
          ours = Setup.of(computer.address_bus)
          raise FormatError, "the snapshot is of a machine with #{setup}, not #{ours}" unless setup == ours

          apply(container, setup.build)
          prepare(computer)
          report = apply(container, computer)
          Report.new(applied: report.applied, ignored: report.ignored + drives(computer))
        end

        # Applies the modules badline reads to a machine built as the
        # snapshot's was (setup), and returns the Report.
        def apply(container, computer)
          applied = []
          ignored = []
          READ.each do |name|
            section = find(name, container)
            next unless section

            reason = refusal(name, section, container)
            if reason
              ignored << "#{section}: #{reason}, left out"
            else
              import_module(name, section, computer)
              applied << section.name
            end
          end
          Report.new(applied:, ignored: ignored + left_out(container, applied))
        end

        # The module a snapshot has for one badline reads, under any of its
        # names.
        def find(name, container)
          case name
          when MainCPU::NAME then MainCPU.find(container)
          when VICII::NAME then VICII.find(container)
          else container[name]
          end
        end

        def prepare(computer)
          computer.address_bus.detach_cartridge if computer.address_bus.cartridge
          computer.power_cycle!
        end

        # Why badline leaves the module out, or nil when it reads it.
        def refusal(name, section, container)
          reason = if !reads?(name, section) then "badline doesn't read this version"
                   elsif name == SIDExtended::NAME && !resid?(container) then "another SID engine wrote it"
                   end
          raise FormatError, "#{section}: #{reason}" if reason && REQUIRED.include?(name)

          reason
        end

        def reads?(name, section)
          case name
          when MainCPU::NAME then MainCPU.reads?(section)
          when C64Mem::NAME then C64Mem.reads?(section)
          when SIDRegisters::NAME then SIDRegisters.reads?(section)
          when SIDExtended::NAME then SIDExtended.reads?(section)
          when VICII::NAME then VICII.reads?(section)
          else CIAs.reads?(section)
          end
        end

        def import_module(name, section, computer)
          case name
          when MainCPU::NAME then MainCPU.import(section, computer)
          when C64Mem::NAME then C64Mem.import(section, computer)
          when SIDRegisters::NAME then SIDRegisters.import(section, computer)
          when SIDExtended::NAME then SIDExtended.import(section, computer)
          when VICII::NAME then VICII.import(section, computer)
          else CIAs.import(section, computer)
          end
        end

        # SIDEXTENDED holds the engine's own state, and badline reads reSID's.
        def resid?(container)
          sid = container[SIDRegisters::NAME]
          !sid.nil? && SIDRegisters.engine(sid) == SIDRegisters::RESID
        end

        def left_out(container, applied)
          read = READ + [MainCPU::TRUNK_NAME, VICII::TRUNK_NAME]
          container.sections.reject { |section| applied.include?(section.name) || read.include?(section.name) }
                   .map { |section| "#{section}: badline doesn't read this module, left out" }
        end

        def drives(computer)
          lines = []
          lines << "the disk mounted in device 8 stays mounted" if computer.mounted?
          lines << "the 1541 stays on the serial bus, reset" if computer.drive1541
          lines
        end
      end
    end
  end
end
