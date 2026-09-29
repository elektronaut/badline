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

      # The modules a badline snapshot carries for VICE, in x64sc's order.
      # They describe a copy of the machine restored from `state`, so saving
      # leaves the machine itself alone. VICE saves between instructions,
      # and resumes by fetching an opcode at the program counter, so when
      # badline's CPU is inside an instruction the copy runs on to its end.
      # The copy's SID catches up, so its registers and voices stand as of
      # that cycle. badline writes no VICE module for an REU or an NTSC
      # VIC-II yet, and fails for a machine with either.
      def self.export(state)
        check_exportable(Computer.setup(state))
        machine = settled(state)
        [MainCPU.export(machine), C64Mem.export(machine), Peripherals.cartridge_port, *CIAs.export(machine),
         SIDRegisters.export(machine), SIDExtended.export(machine), Peripherals.drives, VICII.export(machine),
         Peripherals.glue(machine), *Peripherals.rest]
      end

      def self.check_exportable(setup)
        raise FormatError, "badline can't save an REU in VICE's terms yet, so can't save this machine" if setup.reu
        return if setup.region == Region::PAL

        raise FormatError, "badline can't save an NTSC VIC-II in VICE's terms yet, so can't save this machine"
      end

      # The copy is detached from the host's files (Snapshot::StateReader),
      # so it reads none and its traps write none.
      def self.settled(state)
        copy = Computer.restored(state, detached: true)
        BOUNDARY_CYCLES.times do
          break if copy.cpu.boundary?

          copy.cycle!
        end
        copy.sid.catch_up!
        copy
      end

      # How the machine the snapshot was saved from was built. VICE doesn't
      # save the CIA model; the C64C's 8565 VIC-II goes with the 6526A. An
      # NTSC or PAL-N VIC-II fails, as badline runs PAL only.
      def self.setup(container)
        vic = VICII.find(container) ? VICII.model(VICII.find(container)) : :mos6569
        sid = container[SIDRegisters::NAME] ? SIDRegisters.model(container[SIDRegisters::NAME]) : :mos6581
        Setup.new(vic_model: vic, cia_model: vic == :mos8565 ? :mos6526a : :mos6526, sid_model: sid,
                  region: Region::PAL, ram_expansion: nil, reu: nil)
      end
    end
  end
end
