# frozen_string_literal: true

module Badline
  module Support
    # A Checkpoint of a KIM-1: its CPU, the 1K of RAM, each 6530's RAM,
    # ports and timer, and the panel's held key and what its digits show.
    module KIM1Checkpoint
      COMPONENTS = %w[cpu ram u2 u3 panel].freeze

      def self.take(machine)
        ram = machine.ram
        Checkpoint.new(machine.cycles, [
                         Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu)),
                         Checkpoint.fnv1a(Checkpoint.ram(ram, ram.length)),
                         Checkpoint.fnv1a(rriot_state(machine.u2)),
                         Checkpoint.fnv1a(rriot_state(machine.u3)),
                         Checkpoint.fnv1a(panel_state(machine.panel))
                       ], COMPONENTS)
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)

      def self.rriot_state(rriot) = rriot.idle_state.map { |value| bit(value) } + [rriot.timer.counter]

      def self.panel_state(panel)
        held = panel.held
        [held.nil? ? -1 : KIM1::Panel::KEYS.index(held), *panel.display]
      end

      def self.bit(value)
        return value if value.is_a?(Integer)

        value ? 1 : 0
      end
    end
  end
end
