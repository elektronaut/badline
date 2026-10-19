# frozen_string_literal: true

require_relative "taken_once"

# PETs for the xpet snapshot specs, and the modules xpet writes for them,
# made by badline: a PET whose CRTC is set up as its editor sets it up,
# running a program that waits for PIA 1's CB1 flag with IRQs off and
# keeps VIA timer 1's count each time it finds it.
module XpetSnapshots
  # At $1800: timer 1 free-running from $FFFF, then for each CB1 flag
  # timer 1's low and high bytes at $1900,X and $1980,X, 64 times, then a
  # loop at DONE.
  PROBE = [0x78, 0xa9, 0x40, 0x8d, 0x4b, 0xe8, 0xa9, 0xff, 0x8d, 0x44, 0xe8, 0x8d, 0x45, 0xe8, 0xad, 0x12, 0xe8,
           0xa2, 0x00, 0xad, 0x13, 0xe8, 0x10, 0xfb, 0xad, 0x44, 0xe8, 0x9d, 0x00, 0x19, 0xad, 0x45, 0xe8, 0x9d,
           0x80, 0x19, 0xad, 0x12, 0xe8, 0xe8, 0xe0, 0x40, 0xd0, 0xe7, 0xee, 0x00, 0x1a, 0x4c, 0x2c, 0x18].freeze
  START = 0x1800
  DONE = 0x182c
  # R0-R13 as the 8032's and the 4032's 50 Hz editors set them.
  CRTC80 = [0x31, 0x28, 0x29, 0x0f, 0x27, 0x00, 0x19, 0x20, 0x00, 0x09, 0x00, 0x00, 0x10, 0x00].freeze
  CRTC40 = [0x31, 0x28, 0x29, 0x0f, 0x31, 0x00, 0x19, 0x25, 0x00, 0x07, 0x00, 0x00, 0x10, 0x00].freeze

  module_function

  def run(machine, cycles)
    cycles.times { machine.cycle! }
    machine
  end

  def to_boundary(machine)
    machine.cycle! until machine.cpu.boundary?
    machine
  end

  # The PET running the program for `cycles`, at an instruction boundary,
  # as a State taken once.
  def probing(model, cycles)
    TakenOnce.fetch([:xpet_probe, model, cycles]) do
      built = model == "superpet" ? Badline::PET::SuperPET.new : Badline::PET.new(model:)
      machine = to_boundary(run(built, 10))
      set_up_crtc(machine, machine.model.video == :crtc80 ? CRTC80 : CRTC40) if machine.model.crtc?
      PROBE.each_with_index { |byte, offset| machine.poke(START + offset, byte) }
      machine.cpu.program_counter = START
      to_boundary(run(machine, cycles)).snapshot
    end
  end

  def set_up_crtc(machine, registers)
    registers.each_with_index do |value, register|
      machine.poke(0xe880, register)
      machine.poke(0xe881, value)
    end
  end

  # The VICE modules xpet reads for the machine, alone.
  def exported(machine)
    sections = Badline::Snapshot::Image.exported(machine).sections.reject { |section| section.name.start_with?("BL-") }
    Badline::Snapshot::Container.new(sections, machine: Badline::Snapshot::Container::PET)
  end

  # The container with the module `name` as the block makes it.
  def with_section(container, name)
    sections = container.sections.map { |section| section.name == name ? yield(section) : section }
    Badline::Snapshot::Container.new(sections, machine: container.machine)
  end

  # The section with `bytes` written over its data at `offset`.
  def patched(section, offset, bytes)
    data = section.data.dup
    bytes.each_with_index { |byte, index| data.setbyte(offset + index, byte) }
    section.with(data:)
  end

  # Timer 1's counts at the CB1 flags the program has found.
  def counts(machine) = Array.new(64) { |index| machine.peek(0x1900 + index) | (machine.peek(0x1980 + index) << 8) }
end
