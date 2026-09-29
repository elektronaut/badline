# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # C64MEM 0.1: the CPU port, the cartridge's EXROM and GAME lines, and
      # the 64K of RAM. The lines are written inactive, to match the empty
      # cartridge port the snapshot shows VICE, and aren't read: badline
      # takes them from its own cartridge.
      #
      # The floating port bits 6 and 7 carry their charge both ways. VICE's
      # clocks for when the charge drains are written as zero and not read:
      # the charge lasts as long as badline holds it.
      module C64Mem
        NAME = "C64MEM"
        MAJOR = 0
        MINOR = 1
        FLOATING = [0x40, 0x80].freeze

        module_function

        def reads?(section) = section.major == MAJOR && section.minor == MINOR

        def export(computer)
          bus = computer.address_bus
          ddr, port_out, floating = bus.port_state
          fields = FieldWriter.new.byte(port_out).byte(ddr).byte(0).byte(0)
          fields.bytes(Array.new(0x10000) { |addr| computer.ram.peek(addr) })
          fields.byte((port_out & ddr) | (floating & ~ddr)).byte(bus.peek(1)).byte(ddr)
          fields.dword(0).dword(0)
          charged = FLOATING.map { |bit| floating.anybits?(bit) }
          draining = FLOATING.map { |bit| floating.anybits?(bit) && ddr.nobits?(bit) }
          (charged + draining).each { |set| fields.flag(set) }
          fields.section(NAME, MAJOR, MINOR)
        end

        # The port is set without a bus write, which would leave the VIC's
        # phi1 byte in the RAM under $00 and $01.
        def import(section, computer)
          fields = FieldReader.new(section)
          data = fields.byte
          ddr = fields.byte
          fields.skip(2) # EXROM and GAME
          computer.ram.write(0, fields.bytes(0x10000))
          fields.skip(3 + 8)
          charge = FLOATING.sum { |bit| fields.flag? ? bit : 0 }
          driven = ddr & AddressBus::PORT_FLOATING
          computer.address_bus.restore_port(ddr, data, (data & driven) | (charge & ~driven & 0xff))
        end
      end
    end
  end
end
