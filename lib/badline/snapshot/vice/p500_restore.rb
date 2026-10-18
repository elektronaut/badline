# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module P500
        # Restores a P500 from a snapshot xcbm5x0 wrote, as CBM2::Restore
        # restores a B series: the modules badline reads become the
        # machine's keyed modules, the CIA, the SID and the VIC read into a
        # machine of their own first. Whatever they don't set stays as the
        # machine has it at power-on, and the disk device 8 serves through
        # the traps stays as it is.
        module Restore
          READ = [MainCPU::NAME, CBM2::CBM2Mem::NAME, "CIA1", *CBM2::TPI::NAMES, CBM2::ACIA::NAME, SIDRegisters::NAME,
                  SIDExtended::NAME, VICII::NAME, MAINS].freeze
          REQUIRED = [MainCPU::NAME, CBM2::CBM2Mem::NAME].freeze
          # The modules read into a machine of their own first.
          CHIPS = %w[BL-CIA BL-SID BL-VIC BL-COLORRAM].freeze

          module_function

          def import(container, computer)
            unless computer.is_a?(Badline::CBM2::P500)
              raise FormatError, "the snapshot is of a P500, not a #{computer_name(computer)}"
            end

            setup = P500.setup(container)
            ours = CBM2Setup.of(computer)
            raise FormatError, "the snapshot is of a #{setup}, not a #{ours}" unless setup == ours

            apply(container, setup.build)
            computer.power_cycle!
            report = apply(container, computer)
            kept = computer.mounted? ? ["the disk mounted in device 8 stays mounted"] : []
            Report.new(applied: report.applied, ignored: report.ignored + kept)
          end

          def computer_name(computer)
            computer.family == :cbm2 ? "CBM-II's B series" : Image::FAMILIES.fetch(computer.family.to_s)
          end

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
            computer.load_modules(Keyed::Modules.new(modules(container, computer, applied)))
            Report.new(applied:, ignored: ignored + CBM2::Restore.left_out(container, applied))
          end

          def refusal(section, container)
            case section.name
            when VICII::NAME then VICII.reads?(section) ? nil : "badline doesn't read this version"
            when MAINS then section.major.zero? && section.minor.zero? ? nil : "badline doesn't read this version"
            else CBM2::Restore.refusal(section, container)
            end
          end

          def modules(container, computer, applied)
            chips = chips(container, computer, applied)
            own = {}
            computer.save_modules.each { |section| own[section.name] = section }
            chips.save_modules.each { |section| own[section.name] = section if CHIPS.include?(section.name) }
            cycles = FieldReader.new(container[MainCPU::NAME]).qword
            high = machine(own, container, computer, cycles, applied)
            own["BL-RAM"] = Keyed.section("BL-RAM") { |out| memory(container[CBM2::CBM2Mem::NAME], out) }
            own["BL-CPU"] = Keyed.section("BL-CPU") { |out| PET::MainCPU.import(container[MainCPU::NAME], out) }
            if applied.include?(CBM2::ACIA::NAME)
              own["BL-ACIA"] = Keyed.section("BL-ACIA") { |out| CBM2::ACIA.import(container[CBM2::ACIA::NAME], out, cycles) }
            end
            lines = CBM2::Restore::IDLE_LINES | (high ? CBM2::Restore::MAINS : 0)
            lines |= CBM2::Restore::CIA unless chips.cia.interrupted?
            lines |= CBM2::Restore::ACIA_LINE unless CBM2::Restore.acia_irq?(container, applied)
            CBM2::Restore.tpis(container, applied, own, lines)
            own.values
          end

          # A machine of its own with xcbm5x0's CIA, SID and VIC read into
          # it.
          def chips(container, computer, applied)
            machine = CBM2::Restore.chips(container, computer, applied)
            VICII.import(container[VICII::NAME], machine.vic, machine.color_ram) if applied.include?(VICII::NAME)
            machine
          end

          # Puts BL-MACHINE in `own`, with the mains' next falling edge where
          # C500DATA has xcbm5x0's tick, and returns whether the mains is
          # high.
          def machine(own, container, computer, cycles, applied)
            half = computer.model.region.clock_hz / (2 * computer.mains_hz)
            tick = applied.include?(MAINS) ? P500.cycles_to_tick(container[MAINS]) : half
            high = true
            own["BL-MACHINE"] = Keyed.section("BL-MACHINE") do |out|
              out.text("family", "cbm2")
              CBM2Setup.of(computer).write_fields(out)
              out.int("cycles", cycles)
              high = CBM2::Mains.write(out, [tick, 1].max, half)
            end
            high
          end

          # The RAM, segment 15's video matrix and the segment registers by
          # their BL-RAM keys.
          def memory(section, out)
            fields = FieldReader.new(section).skip(3)
            out.int("execution_segment", fields.byte & 0x0f).int("indirect_segment", fields.byte & 0x0f)
            system = fields.string(CBM2::CBM2Mem::SYSTEM_RAM)
            out.bytes("system", "\0\0".b + system.byteslice(2, CBM2::CBM2Mem::SYSTEM_RAM - 2))
            out.bytes("screen", fields.string(MATRIX))
            fields.skip(MATRIX)
            Badline::CBM2::P500::Model::RAM_SEGMENTS.each do |segment|
              out.bytes("segment#{segment}", fields.string(CBM2::CBM2Mem::SEGMENT))
            end
          end
        end
      end
    end
  end
end
