# frozen_string_literal: true

require_relative "pet_checkpoint"

module Badline
  module Support
    # A Checkpoint of a SuperPET: the PET's components (PETCheckpoint), the
    # board's latches and bank RAM, the 6702, the ACIA, the 6809 with
    # whether it has the bus, and the traps on the Waterloo ROM's IEEE-488
    # routines, empty without a disk on device 8.
    module SuperPETCheckpoint
      COMPONENTS = (PETCheckpoint::COMPONENTS + %w[board dongle acia m6809 waterloo]).freeze

      def self.take(machine)
        pet = PETCheckpoint.take(machine)
        board = machine.board
        dongle = machine.dongle
        acia = machine.acia
        Checkpoint.new(machine.cycles, pet.digests + [
          Checkpoint.fnv1a([board.bank_latch, board.system_latch, board.socket, *board.cells]),
          Checkpoint.fnv1a(dongle.registers + [dongle.latch, dongle.shift_at]),
          Checkpoint.fnv1a([acia.command, acia.control, acia.status, acia.due]),
          Checkpoint.fnv1a(m6809_state(machine.m6809) + [machine.m6809_running? ? 1 : 0]),
          Checkpoint.fnv1a(machine.waterloo_traps&.state || [])
        ], COMPONENTS)
      end

      def self.m6809_state(cpu)
        [cpu.a, cpu.b, cpu.x, cpu.y, cpu.u, cpu.s, cpu.pc, cpu.dp, cpu.cc, cpu.cycles]
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)
    end
  end
end
