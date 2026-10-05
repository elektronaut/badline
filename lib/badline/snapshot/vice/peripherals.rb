# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # The modules x64sc refuses a snapshot without, for the parts badline
      # doesn't model in VICE's terms: the cartridge port, the file system
      # drives, the glue logic, memory expansions, the tape port, the
      # control ports and the user port. Each is written as a machine with
      # nothing attached leaves it, with the joysticks released and the
      # glue logic's VIC bank taken from CIA 2. A cartridge or tape badline
      # has attached is carried by the BADLINE module only, and an REU by
      # REU1764 as well.
      module Peripherals
        # The glue logic's VIC bank, and its pending bank change.
        GLUE = "GLUE"

        FIXED = [
          ["C64CART", 0, 1, [0x00]], # no cartridge
          ["FSDRIVE", 0, 0, Array.new(258, 0)] # no file system drive open
        ].freeze

        AFTER_VIC = [
          ["C64MEMHACKS", 0, 0, [0x00]], # no memory expansion hack
          ["TAPEPORT", 1, 0, [0x01, 0x01]], # tape port on, datasette in it
          ["JOYPORT0", 0, 0, [0x01]], ["JOYSTICK0", 1, 2, [0x00, 0x00]], # joysticks, released
          ["JOYPORT1", 0, 0, [0x01]], ["JOYSTICK1", 1, 2, [0x00, 0x00]],
          ["USERPORT", 1, 0, [0x01, 0x00]] # user port on, nothing in it
        ].freeze

        module_function

        # C64CART 0.1 lists the REU as the one cartridge in the port when
        # there is one, which REU1764 follows: no main slot cartridge, the
        # lines inactive, no freeze or NMI pending, then the REU's id.
        def cartridge_port(computer)
          return section(*FIXED[0]) unless computer.reu

          fields = FieldWriter.new.byte(1).dword(-1).byte(0).byte(0).dword(0).dword(0).byte(0).byte(0).byte(0)
          fields.qword(-1).qword(-1).zeros(12 + 16).dword(REU1764::CARTRIDGE_ID)
          fields.section("C64CART", 0, 1)
        end

        def drives = section(*FIXED[1])

        def glue(computer)
          bank = ~computer.cia2.port_a_lines & 0x03
          FieldWriter.new.byte(0).byte(bank).byte(0).section(GLUE, 1, 0)
        end

        def rest = AFTER_VIC.map { |entry| section(*entry) }

        def section(name, major, minor, bytes) = FieldWriter.new.bytes(bytes).section(name, major, minor)
      end
    end
  end
end
