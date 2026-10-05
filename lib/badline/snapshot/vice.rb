# frozen_string_literal: true

require "badline/snapshot/vice/main_cpu"
require "badline/snapshot/vice/c64_mem"
require "badline/snapshot/vice/cias"
require "badline/snapshot/vice/cias_import"
require "badline/snapshot/vice/sid_registers"
require "badline/snapshot/vice/sid_extended"
require "badline/snapshot/vice/reu1764"
require "badline/snapshot/vice/peripherals"
require "badline/snapshot/vice/vicii"
require "badline/snapshot/vice/vicii_import"
require "badline/snapshot/vice/restore"

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
      # Cycles more it may run for an REU transfer in flight to end: a
      # swap of 64K, two cycles a byte, stretched by the VIC's holds on
      # the bus.
      TRANSFER_CYCLES = 0x40000

      # The modules a badline snapshot carries for VICE, in x64sc's order.
      # They describe a copy of the machine restored from `state`, so saving
      # leaves the machine itself alone. VICE saves between instructions,
      # and resumes by fetching an opcode at the program counter, so when
      # badline's CPU is inside an instruction, or an REU transfer holds
      # the bus, the copy runs on to the end of both. The copy's SID
      # catches up, so its registers and voices stand as of that cycle.
      def self.export(state)
        machine = settled(state)
        sections = [MainCPU.export(machine), C64Mem.export(machine), Peripherals.cartridge_port(machine)]
        sections << REU1764.export(machine) if machine.reu
        sections + [*CIAs.export(machine), SIDRegisters.export(machine), SIDExtended.export(machine),
                    Peripherals.drives, VICII.export(machine), Peripherals.glue(machine), *Peripherals.rest]
      end

      # The copy is detached from the host's files (Snapshot::StateReader),
      # so it reads none and its traps write none.
      def self.settled(state)
        copy = Computer.restored(state, detached: true)
        (BOUNDARY_CYCLES + TRANSFER_CYCLES).times do
          break if copy.cpu.boundary? && !copy.reu&.dma?

          copy.cycle!
        end
        copy.sid.catch_up!
        copy
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
        Setup.new(vic_model: model, cia_model: model == :mos8565 ? :mos6526a : :mos6526, sid_model: sid,
                  region: vic ? VICII.region(vic) : Region::PAL, ram_expansion: nil,
                  reu: reu ? REU1764.size_kb(reu) : nil, kernal: :c64, datasette: true)
      end
    end
  end
end
