# frozen_string_literal: true

module Badline
  module Support
    # A Checkpoint of a PET: its CPU, the RAM below $8000, the screen RAM,
    # the picture the video paints, both PIAs, the VIA, the CRTC's
    # registers and counters, and the 8096's control register and 64K
    # board, or nothing on another model.
    module PETCheckpoint
      COMPONENTS = %w[cpu ram screen display pia1 pia2 via crtc expansion].freeze

      def self.take(machine)
        ram = machine.ram
        Checkpoint.new(machine.cycles, [
                         Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu)),
                         Checkpoint.fnv1a(Checkpoint.ram(ram, ram.length)),
                         Checkpoint.fnv1a(machine.bus.screen.cells),
                         Checkpoint.fnv1a(machine.video.display),
                         Checkpoint.fnv1a(pia_state(machine.pia1)),
                         Checkpoint.fnv1a(pia_state(machine.pia2)),
                         Checkpoint.fnv1a(Vic20Checkpoint.via_state(machine.via)),
                         Checkpoint.fnv1a(crtc_state(machine.crtc)),
                         Checkpoint.fnv1a(expansion_state(machine.bus.expansion))
                       ], COMPONENTS)
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)

      def self.pia_state(pia) = [pia.port_a_output, pia.port_b_output, pia.cra, pia.crb]

      def self.crtc_state(crtc) = crtc.registers + [crtc.column, crtc.line, crtc.row]

      def self.expansion_state(expansion)
        expansion ? [expansion.control, *expansion.cells] : []
      end
    end
  end
end
