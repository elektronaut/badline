# frozen_string_literal: true

module Badline
  module Support
    # A Checkpoint of a CBM-II: its CPU with both segment registers, the
    # 2K of segment 15's RAM, the RAM board's segments, the screen RAM, the
    # CRTC's registers and counters, the CIA, the ACIA's registers and both
    # TPIs.
    module CBM2Checkpoint
      COMPONENTS = %w[cpu ram segments screen crtc cia acia tpi1 tpi2].freeze

      def self.take(machine)
        bus = machine.bus
        Checkpoint.new(machine.cycles, [
                         Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu) +
                                          [bus.execution_segment, bus.indirect_segment]),
                         Checkpoint.fnv1a(Checkpoint.ram(bus.ram, 0x800)),
                         Checkpoint.fnv1a(segments(bus)),
                         Checkpoint.fnv1a(Array.new(0x800) { |offset| bus.screen.peek(0xd000 + offset) }),
                         Checkpoint.fnv1a(crtc_state(machine.crtc)),
                         Checkpoint.fnv1a(Checkpoint.cia_state(machine.cia)),
                         Checkpoint.fnv1a(acia_state(machine.acia)),
                         Checkpoint.fnv1a(tpi_state(machine.tpi1)),
                         Checkpoint.fnv1a(tpi_state(machine.tpi2))
                       ], COMPONENTS)
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)

      # Every byte of the segments the RAM board fills, segment by segment.
      def self.segments(bus)
        bytes = []
        bus.segment_ram.each { |memory| bytes.concat(Checkpoint.ram(memory, 0x10000)) if memory }
        bytes
      end

      def self.crtc_state(crtc) = crtc.registers + [crtc.column, crtc.line, crtc.row]

      def self.acia_state(acia) = [acia.command, acia.control, acia.status]

      def self.tpi_state(tpi)
        [tpi.port_a_output, tpi.port_b_output, tpi.port_c_output, tpi.latches, tpi.mask, tpi.control,
         tpi.irq? ? 1 : 0, *tpi.stack]
      end
    end
  end
end
