# frozen_string_literal: true

require "badline/snapshot/vice/vic20_cpu"
require "badline/snapshot/vice/vic20_mem"
require "badline/snapshot/vice/vic20_vici"
require "badline/snapshot/vice/vic20_restore"

module Badline
  module Snapshot
    module Vice
      # xvic's modules for the VIC-20, PAL and NTSC: the CPU, the RAM, the
      # VIC-I with the colour RAM, and both VIAs, written from badline's
      # machine and read into it. Each module's file says what maps and
      # what is approximated. The VIAs' are xpet's (PET::VIA). They go
      # through the machine's own keyed fields (Keyed), which a save writes
      # and a load reads.
      module Vic20
        # The modules xvic 3.10 resets the machine without, each as xvic
        # leaves them with nothing attached: no cartridge, no file system
        # drive open, the cassette port on with a datasette in it, the
        # control port on with the joystick released, and nothing in the
        # user port. With no drive modules xvic keeps its own drives as they
        # are.
        CARTRIDGE = ["VIC20CART", 2, 1, [0xff, 0xff, 0xff, 0xff, 0x00]].freeze
        PERIPHERALS = [
          ["FSDRIVE", 0, 0, Array.new(258, 0)], ["TAPEPORT", 1, 0, [0x01, 0x01]], ["JOYPORT0", 0, 0, [0x01]],
          ["JOYSTICK0", 1, 2, [0x00, 0x00]], ["USERPORT", 1, 0, [0x01, 0x00]]
        ].freeze

        module_function

        # The modules xvic 3.10 needs, in its order, describing `machine`,
        # which Machine::Settling has brought between instructions, from
        # its keyed modules, `sections`.
        def export(machine, sections)
          readers = {}
          sections.each { |section| readers[section.name] = Keyed::Reader.parse(section) }
          [MainCPU.export(machine), Mem.export(machine, reader(readers, "BL-MACHINE")), section(*CARTRIDGE),
           VICI.export(machine, reader(readers, "BL-VICI"), reader(readers, "BL-COLORRAM")),
           PET::VIA.export(reader(readers, "BL-VIA1"), "VIA1"), PET::VIA.export(reader(readers, "BL-VIA2"), "VIA2")] +
            PERIPHERALS.map { |entry| section(*entry) }
        end

        def section(name, major, minor, bytes) = FieldWriter.new.bytes(bytes).section(name, major, minor)

        def reader(readers, name) = readers[name] || Keyed::Reader.missing(name)

        # How the machine xvic saved was built: the RAM from VIC20MEM's
        # blocks, and the model from the lines of the VIC-I's picture.
        def setup(container)
          memory = container[Mem::NAME]
          raise FormatError, "the snapshot has no #{Mem::NAME} module" if memory.nil?
          raise FormatError, "#{memory}: badline doesn't read this version" unless Mem.reads?(memory)

          ram = Mem.ram_configuration(memory)
          raise FormatError, "#{memory}: RAM in blocks badline doesn't fit together" if ram.nil?

          Vic20Setup.new(ram:, model: model(container))
        end

        def model(container)
          vic = container[VICI::NAME]
          return "pal" if vic.nil? || !VICI.reads?(vic)

          VICI.model(vic) || raise(FormatError, "#{vic}: a picture of a size badline's VIC-Is don't draw")
        end
      end
    end
  end
end
