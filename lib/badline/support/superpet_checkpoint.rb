# frozen_string_literal: true

require_relative "pet_checkpoint"

module Badline
  module Support
    # A Checkpoint of a SuperPET: the PET's components (PETCheckpoint), the
    # board's latches and bank RAM, the 6702 and the ACIA.
    module SuperPETCheckpoint
      COMPONENTS = (PETCheckpoint::COMPONENTS + %w[board dongle acia]).freeze

      def self.take(machine)
        pet = PETCheckpoint.take(machine)
        board = machine.board
        dongle = machine.dongle
        acia = machine.acia
        Checkpoint.new(machine.cycles, pet.digests + [
          Checkpoint.fnv1a([board.bank_latch, board.system_latch, board.socket, *board.cells]),
          Checkpoint.fnv1a(dongle.registers + [dongle.latch, dongle.shift_at]),
          Checkpoint.fnv1a([acia.command, acia.control, acia.status, acia.due])
        ], COMPONENTS)
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)
    end
  end
end
