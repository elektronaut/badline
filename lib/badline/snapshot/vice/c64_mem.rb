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

        def export(computer)
          bus = computer.address_bus
          ddr = bus.peek(0)
          port_out = bus.instance_variable_get(:@port_out)
          floating = bus.instance_variable_get(:@port_floating)
          fields = FieldWriter.new.byte(port_out).byte(ddr).byte(0).byte(0)
          fields.bytes(Array.new(0x10000) { |addr| computer.ram.peek(addr) })
          fields.byte((port_out & ddr) | (floating & ~ddr)).byte(bus.peek(1)).byte(ddr)
          fields.dword(0).dword(0)
          charged = FLOATING.map { |bit| floating.anybits?(bit) }
          draining = FLOATING.map { |bit| floating.anybits?(bit) && ddr.nobits?(bit) }
          (charged + draining).each { |set| fields.flag(set) }
          fields.section(NAME, MAJOR, MINOR)
        end

        def import(section, computer)
          fields = FieldReader.new(section)
          data = fields.byte
          ddr = fields.byte
          fields.skip(2) # EXROM and GAME
          computer.ram.write(0, fields.bytes(0x10000))
          fields.skip(3 + 8)
          charge = FLOATING.sum { |bit| fields.flag? ? bit : 0 }
          port(computer.address_bus, data, ddr, charge)
        end

        def port(bus, data, ddr, charge)
          bus.poke(0, ddr)
          bus.poke(1, data)
          floating = bus.instance_variable_get(:@port_floating)
          bus.instance_variable_set(:@port_floating, (floating & ddr) | (charge & ~ddr & 0xff))
          bus.send(:update_port!)
        end
      end
    end
  end
end
