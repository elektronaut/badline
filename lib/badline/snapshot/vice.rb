# frozen_string_literal: true

require "badline/snapshot/vice/main_cpu"
require "badline/snapshot/vice/c64_mem"
require "badline/snapshot/vice/cias"
require "badline/snapshot/vice/cias_import"
require "badline/snapshot/vice/sid_registers"
require "badline/snapshot/vice/sid_extended"
require "badline/snapshot/vice/peripherals"
require "badline/snapshot/vice/vicii"
require "badline/snapshot/vice/vicii_import"

module Badline
  module Snapshot
    # VICE's own modules for the chips both emulators model, written from
    # and read into badline's machine. Each module's file says what maps
    # and what is approximated. Reading a snapshot from VICE starts from a
    # machine at power-on and applies the modules it has, in the order x64sc
    # writes them.
    module Vice
      # Cycles a copy of the machine may run to reach an instruction
      # boundary: the longest instruction, stretched by the VIC's longest
      # hold on the bus.
      BOUNDARY_CYCLES = 100

      # The modules a badline snapshot carries for VICE, in x64sc's order.
      # They describe a copy of the machine restored from `state`, the
      # BADLINE module, so saving leaves the machine itself alone. VICE
      # saves between instructions, and resumes by fetching an opcode at the
      # program counter, so when badline's CPU is inside an instruction the
      # copy runs on to its end. The copy's SID catches up, so its registers
      # and voices stand as of that cycle.
      def self.export(state)
        machine = settled(state)
        [MainCPU.export(machine), C64Mem.export(machine), Peripherals.cartridge_port, *CIAs.export(machine),
         SIDRegisters.export(machine), SIDExtended.export(machine), Peripherals.drives, VICII.export(machine),
         Peripherals.glue(machine), *Peripherals.rest]
      end

      def self.settled(state)
        copy = Computer.new(**MachineState.models(state))
        MachineState.restore(state, copy)
        BOUNDARY_CYCLES.times do
          break if boundary?(copy.cpu)

          copy.cycle!
        end
        copy.sid.send(:catch_up)
        copy
      end

      def self.boundary?(cpu) = cpu.instance_variable_get(:@plan).equal?(CPU::FETCH_PLAN)

      # The modules badline reads, in the order it applies them: the VIC
      # comes last, as it is clocked to its cycle through memory and CIA 2.
      READERS = [[MainCPU, "MAINCPU"], [C64Mem, "C64MEM"], [CIAs, "CIA1"], [CIAs, "CIA2"],
                 [SIDRegisters, "SID"], [SIDExtended, "SIDEXTENDED"], [VICII, "VIC-II"]].freeze

      # The chip models the snapshot's machine was built with. VICE doesn't
      # save the CIA model; the C64C's 8565 VIC-II goes with the 6526A.
      def self.models(container)
        vic = container[VICII::NAME] ? VICII.model(container[VICII::NAME]) : :mos6569
        sid = container[SIDRegisters::NAME] ? SIDRegisters.model(container[SIDRegisters::NAME]) : :mos6581
        { vic_model: vic, cia_model: vic == :mos8565 ? :mos6526a : :mos6526, sid_model: sid }
      end

      # Applies the modules badline reads to `computer`, and returns a
      # Report naming what it applied and, with a reason, what it left out.
      def self.import(container, computer)
        applied = READERS.filter_map do |reader, name|
          section = container[name]
          next unless section && (reader != SIDExtended || resid?(container))

          reader.import(section, computer)
          name
        end
        Report.new(applied:, ignored: ignored(container, applied))
      end

      # SIDEXTENDED holds the engine's own state, and badline reads reSID's.
      def self.resid?(container)
        sid = container[SIDRegisters::NAME]
        !sid.nil? && SIDRegisters.engine(sid) == SIDRegisters::RESID
      end

      def self.ignored(container, applied)
        container.sections.reject { |section| applied.include?(section.name) }.map do |section|
          "#{section.name} #{section.version}: badline doesn't read this module, left out"
        end
      end
    end
  end
end
