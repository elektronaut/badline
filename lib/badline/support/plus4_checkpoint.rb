# frozen_string_literal: true

module Badline
  module Support
    # A Checkpoint of a 264 series machine: its CPU, its RAM, the TED's
    # picture, the TED's registers, timers and beam, its sound, and the
    # CPU's port with the ROM banks. The sound's voices are run up to the
    # cycle to read them, which changes nothing they do.
    module Plus4Checkpoint
      COMPONENTS = %w[cpu ram display ted sound port].freeze

      def self.take(machine)
        ram = machine.ram
        Checkpoint.new(machine.cycles, [
                         Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu)),
                         Checkpoint.fnv1a(Checkpoint.ram(ram, ram.length)),
                         Checkpoint.fnv1a(machine.ted.display),
                         Checkpoint.fnv1a(ted_state(machine.ted)),
                         Checkpoint.fnv1a(sound_state(machine.sound)),
                         Checkpoint.fnv1a(port_state(machine))
                       ], COMPONENTS)
      end

      def self.parse(line) = Checkpoint.parse(line, COMPONENTS)

      def self.ted_state(ted)
        Array.new(0x20) { |register| ted.peek(0xff00 + register) } +
          ted.timer_counts + [ted.line, ted.column, ted.interrupt_flags, ted.cpu_slots]
      end

      def self.sound_state(sound)
        [sound.noise, sound.phase(0), sound.phase(1), sound.level, sound.volume, sound.control]
      end

      def self.port_state(machine)
        port = machine.port
        bus = machine.bus
        [port.ddr, port.data, bus.low_bank, bus.high_bank, bus.rom_selected ? 1 : 0]
      end
    end
  end
end
