# frozen_string_literal: true

require_relative "taken_once"

# VIC-20s for the xvic snapshot specs, made by badline: the KERNAL's text
# window set up, VIA 2's timer 1 free-running with its interrupt enabled
# and IRQs off, and a loop counting at $1100.
module XvicSnapshots
  # At $1000: the window's registers from WINDOW at $1040 into the VIC,
  # the timer and its interrupt, then the loop.
  PROBE = [0x78, 0xa2, 0x0f, 0xbd, 0x40, 0x10, 0x9d, 0x00, 0x90, 0xca, 0x10, 0xf7, 0xa9, 0x40, 0x8d, 0x2b, 0x91,
           0xa9, 0xc0, 0x8d, 0x2e, 0x91, 0xa9, 0x34, 0x8d, 0x24, 0x91, 0xa9, 0x12, 0x8d, 0x25, 0x91, 0xee, 0x00,
           0x11, 0x4c, 0x20, 0x10].freeze
  WINDOW = [0x0c, 0x26, 0x96, 0x2e, 0x00, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1b].freeze
  START = 0x1000

  module_function

  # A VIC-20 running the probe for `cycles`, at an instruction boundary,
  # as a snapshot taken once.
  def probing(ram, model, cycles)
    TakenOnce.fetch([:xvic_probe, ram, model, cycles]) do
      machine = Badline::Vic20.new(ram:, model:)
      bytes = PROBE + Array.new(0x40 - PROBE.length, 0) + WINDOW
      bytes.each_with_index { |byte, offset| machine.poke(START + offset, byte) }
      machine.cpu.program_counter = START
      cycles.times { machine.cycle! }
      machine.cycle! until machine.cpu.boundary?
      machine.snapshot
    end
  end

  # The VICE modules xvic reads for the machine, alone.
  def exported(machine)
    sections = Badline::Snapshot::Image.exported(machine).sections.reject { |section| section.name.start_with?("BL-") }
    Badline::Snapshot::Container.new(sections, machine: Badline::Snapshot::Container::VIC20)
  end
end
