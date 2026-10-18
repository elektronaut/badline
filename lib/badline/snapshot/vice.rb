# frozen_string_literal: true

require "badline/snapshot/vice/fields"
require "badline/snapshot/vice/main_cpu"
require "badline/snapshot/vice/c64_mem"
require "badline/snapshot/vice/cias"
require "badline/snapshot/vice/cias_import"
require "badline/snapshot/vice/sid_registers"
require "badline/snapshot/vice/sid_extended"
require "badline/snapshot/vice/reu_fields"
require "badline/snapshot/vice/reu1764"
require "badline/snapshot/vice/peripherals"
require "badline/snapshot/vice/vicii"
require "badline/snapshot/vice/vicii_import"
require "badline/snapshot/vice/restore"
require "badline/snapshot/vice/pet"
require "badline/snapshot/vice/cbm2"
require "badline/snapshot/vice/p500"
require "badline/snapshot/vice/p500_restore"

module Badline
  module Snapshot
    # VICE's own modules for the chips both emulators model, written from
    # and read into badline's machine. Each module's file says what maps
    # and what is approximated. Reading a snapshot from VICE starts from a
    # machine at power-on with nothing attached, and applies the modules it
    # has, in the order x64sc writes them.
    module Vice
      # The modules a badline snapshot carries for VICE, in x64sc's order,
      # describing `machine`, which Machine::Settling has brought between
      # instructions with no REU transfer under way: VICE saves between
      # instructions, and resumes by fetching an opcode at the program
      # counter. Its SID has caught up, so the registers and voices stand
      # as of that cycle.
      def self.export(machine)
        sections = [MainCPU.export(machine), C64Mem.export(machine), Peripherals.cartridge_port(machine)]
        sections << REU1764.export(machine) if machine.reu
        sections + [*CIAs.export(machine), SIDRegisters.export(machine), SIDExtended.export(machine),
                    Peripherals.drives, VICII.export(machine), Peripherals.glue(machine), *Peripherals.rest]
      end

      # How the machine the snapshot was saved from was built: the VIC
      # model and the region from the VIC-II's model, and an REU from
      # REU1764. VICE doesn't save the CIA model; the 8565 and 8562 go
      # with the 6526A.
      def self.setup(container)
        vic = VICII.find(container)
        model = vic ? VICII.model(vic) : :mos6569
        sid = container[SIDRegisters::NAME] ? SIDRegisters.model(container[SIDRegisters::NAME]) : :mos6581
        reu = container[REU1764::NAME]
        reu = nil unless reu && REU1764.reads?(reu)
        C64Setup.new(vic_model: model, cia_model: model == :mos8565 ? :mos6526a : :mos6526, sid_model: sid,
                     region: vic ? VICII.region(vic) : Region::PAL, ram_expansion: nil,
                     reu: reu ? REU1764.size_kb(reu) : nil, kernal: :c64, datasette: true,
                     board: :c64)
      end
    end
  end
end
