# frozen_string_literal: true

module Badline
  module Support
    # A Checkpoint of a P500: its CPU with both segment registers, the 2K
    # of segment 15's RAM, segments 0 and 1, the static video matrix, the
    # colour RAM's nibbles, the picture, the VIC's registers and beam, the
    # SID's registers, the CIA, the ACIA's registers and both TPIs, the
    # last three as CBM2Checkpoint digests them.
    module P500Checkpoint
      COMPONENTS = %w[cpu ram segments screen color_ram display vic sid cia acia tpi1 tpi2].freeze

      def self.take(machine)
        bus = machine.bus
        Checkpoint.new(machine.cycles, [
                         Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu) +
                                          [bus.execution_segment, bus.indirect_segment]),
                         Checkpoint.fnv1a(Checkpoint.ram(bus.ram, 0x800)),
                         Checkpoint.fnv1a(CBM2Checkpoint.segments(bus)),
                         Checkpoint.fnv1a(Array.new(0x400) { |offset| bus.screen.peek(0xd000 + offset) }),
                         Checkpoint.fnv1a(Checkpoint.color_ram(machine.color_ram, 0xd400)),
                         Checkpoint.fnv1a(machine.vic.display),
                         Checkpoint.fnv1a(Checkpoint.vic_state(machine.vic)),
                         Checkpoint.fnv1a(Array.new(0x20) { |reg| machine.sid.register(reg) }),
                         Checkpoint.fnv1a(Checkpoint.cia_state(machine.cia)),
                         Checkpoint.fnv1a(CBM2Checkpoint.acia_state(machine.acia)),
                         Checkpoint.fnv1a(CBM2Checkpoint.tpi_state(machine.tpi1)),
                         Checkpoint.fnv1a(CBM2Checkpoint.tpi_state(machine.tpi2))
                       ], COMPONENTS)
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)
    end
  end
end
