# frozen_string_literal: true

module Badline
  # A Checkpoint of a C128, in either mode: a C64's components, with the
  # whole 128K of RAM in place of bank 0 and the colour RAM bank the 8502
  # sees, and besides them the VDC's registers and beam, the VDC's RAM, the
  # MMU's registers and the Z80.
  module C128Checkpoint
    COMPONENTS = %w[cpu ram color_ram display vic cia1 cia2 sid vdc vdc_ram mmu z80].freeze

    def self.take(machine)
      Checkpoint.new(machine.cycles, [
                       Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu)),
                       Checkpoint.fnv1a(Checkpoint.ram(machine.ram, 0x20000)),
                       Checkpoint.fnv1a(Checkpoint.color_ram(machine.address_bus.color_ram, 0xd800)),
                       Checkpoint.fnv1a(machine.vic.display),
                       Checkpoint.fnv1a(Checkpoint.vic_state(machine.vic)),
                       Checkpoint.fnv1a(Checkpoint.cia_state(machine.cia1)),
                       Checkpoint.fnv1a(Checkpoint.cia_state(machine.cia2)),
                       Checkpoint.fnv1a(Array.new(0x20) { |reg| machine.sid.register(reg) }),
                       Checkpoint.fnv1a(machine.vdc.registers + [machine.vdc.frame]),
                       Checkpoint.fnv1a(machine.vdc.ram),
                       Checkpoint.fnv1a(machine.mmu.registers),
                       Checkpoint.fnv1a(z80_state(machine.z80))
                     ], COMPONENTS)
    end

    def self.parse(line) = Checkpoint.parse(line, COMPONENTS)

    def self.z80_state(z80)
      [z80.pc, z80.sp, z80.af, z80.bc, z80.de, z80.hl, z80.ix, z80.iy, z80.af_alt, z80.bc_alt, z80.de_alt,
       z80.hl_alt, z80.i, z80.r, z80.im, flag(z80.iff1), flag(z80.iff2), flag(z80.halted), z80.cycles]
    end

    def self.flag(value) = value == true ? 1 : 0
  end
end
