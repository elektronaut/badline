# frozen_string_literal: true

module Badline
  # A Checkpoint of a VIC-20: its CPU, the 48K of RAM the bus decodes, the
  # colour RAM, the VIC-I's display and registers, both VIAs and the
  # sound. The sound's shift registers and noise LFSR move only while it
  # records, so a run that wants them digested records it.
  module Vic20Checkpoint
    COMPONENTS = %w[cpu ram color_ram display vic via1 via2 sound].freeze

    def self.take(machine)
      Checkpoint.new(machine.cycles, [
                       Checkpoint.fnv1a(Checkpoint.cpu_state(machine.cpu)),
                       Checkpoint.fnv1a(Checkpoint.ram(machine.ram, 0xc000)),
                       Checkpoint.fnv1a(Checkpoint.color_ram(machine.bus.color_ram, 0)),
                       Checkpoint.fnv1a(machine.vic.display),
                       Checkpoint.fnv1a(Checkpoint.vic_state(machine.vic)),
                       Checkpoint.fnv1a(via_state(machine.via1)),
                       Checkpoint.fnv1a(via_state(machine.via2)),
                       Checkpoint.fnv1a(sound_state(machine.sound))
                     ], COMPONENTS)
    end

    def self.parse(line) = Checkpoint.parse(line, COMPONENTS)

    def self.via_state(via)
      [via.port_a_output, via.port_b_output, via.timer1, via.timer1_latch, via.timer2,
       via.shift_register.data, via.acr, via.pcr, via.interrupt_flags, via.interrupt_enable]
    end

    def self.sound_state(sound)
      [sound.volume, sound.shift_register(0), sound.shift_register(1), sound.shift_register(2),
       sound.shift_register(3), sound.lfsr]
    end
  end
end
