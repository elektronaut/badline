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
    # machine at power-on with nothing attached, and applies the modules it
    # has, in the order x64sc writes them.
    module Vice
      # Cycles a copy of the machine may run to reach an instruction
      # boundary: the longest instruction, stretched by the VIC's longest
      # hold on the bus.
      BOUNDARY_CYCLES = 100

      # The modules a badline snapshot carries for VICE, in x64sc's order.
      # They describe a copy of the machine restored from `state`, so saving
      # leaves the machine itself alone. VICE saves between instructions,
      # and resumes by fetching an opcode at the program counter, so when
      # badline's CPU is inside an instruction the copy runs on to its end.
      # The copy's SID catches up, so its registers and voices stand as of
      # that cycle.
      def self.export(state)
        machine = settled(state)
        [MainCPU.export(machine), C64Mem.export(machine), Peripherals.cartridge_port, *CIAs.export(machine),
         SIDRegisters.export(machine), SIDExtended.export(machine), Peripherals.drives, VICII.export(machine),
         Peripherals.glue(machine), *Peripherals.rest]
      end

      def self.settled(state)
        copy = Computer.setup(state).build.restore(state)
        BOUNDARY_CYCLES.times do
          break if copy.cpu.boundary?

          copy.cycle!
        end
        copy.sid.catch_up!
        copy
      end

      # The modules badline reads, in the order it applies them: the VIC
      # comes last, as it is clocked to its cycle through memory and CIA 2.
      # MAINCPU and C64MEM hold the machine itself, so a version badline
      # doesn't read fails the restore; the others are left out and
      # reported.
      READ = [MainCPU::NAME, C64Mem::NAME, "CIA1", "CIA2", SIDRegisters::NAME, SIDExtended::NAME,
              VICII::NAME].freeze
      REQUIRED = [MainCPU::NAME, C64Mem::NAME].freeze

      # How the machine the snapshot was saved from was built. VICE doesn't
      # save the CIA model; the C64C's 8565 VIC-II goes with the 6526A. An
      # NTSC or PAL-N VIC-II fails, as badline runs PAL only.
      def self.setup(container)
        vic = container[VICII::NAME] ? VICII.model(container[VICII::NAME]) : :mos6569
        sid = container[SIDRegisters::NAME] ? SIDRegisters.model(container[SIDRegisters::NAME]) : :mos6581
        Setup.new(vic_model: vic, cia_model: vic == :mos8565 ? :mos6526a : :mos6526, sid_model: sid,
                  region: Region::PAL, ram_expansion: nil)
      end

      # Applies the modules badline reads to `computer`, and returns a
      # Report naming what it applied and, with a reason, what it left out.
      # The machine is taken to power-on with its cartridge out first, so
      # nothing it was doing carries into the snapshot's machine.
      def self.import(container, computer)
        setup(container)
        prepare(computer)
        applied = []
        ignored = []
        READ.each do |name|
          section = name == MainCPU::NAME ? MainCPU.find(container) : container[name]
          next unless section

          reason = refusal(name, section, container)
          if reason
            ignored << "#{section}: #{reason}, left out"
          else
            import_module(name, section, computer)
            applied << section.name
          end
        end
        Report.new(applied:, ignored: ignored + left_out(container, applied) + drives(computer))
      end

      def self.prepare(computer)
        computer.address_bus.detach_cartridge if computer.address_bus.cartridge
        computer.power_cycle!
      end

      # Why badline leaves the module out, or nil when it reads it.
      def self.refusal(name, section, container)
        reason = if !reads?(name, section) then "badline doesn't read this version"
                 elsif name == SIDExtended::NAME && !resid?(container) then "another SID engine wrote it"
                 end
        raise FormatError, "#{section}: #{reason}" if reason && REQUIRED.include?(name)

        reason
      end

      def self.reads?(name, section)
        case name
        when MainCPU::NAME then MainCPU.reads?(section)
        when C64Mem::NAME then C64Mem.reads?(section)
        when SIDRegisters::NAME then SIDRegisters.reads?(section)
        when SIDExtended::NAME then SIDExtended.reads?(section)
        when VICII::NAME then VICII.reads?(section)
        else CIAs.reads?(section)
        end
      end

      def self.import_module(name, section, computer)
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
      def self.resid?(container)
        sid = container[SIDRegisters::NAME]
        !sid.nil? && SIDRegisters.engine(sid) == SIDRegisters::RESID
      end

      def self.left_out(container, applied)
        read = READ + [MainCPU::TRUNK_NAME]
        container.sections.reject { |section| applied.include?(section.name) || read.include?(section.name) }
                 .map { |section| "#{section}: badline doesn't read this module, left out" }
      end

      def self.drives(computer)
        lines = []
        lines << "the disk mounted in device 8 stays mounted" if computer.mounted?
        lines << "the 1541 stays on the serial bus, reset" if computer.drive1541
        lines
      end
    end
  end
end
