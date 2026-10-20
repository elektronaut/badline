# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module Vic20
        # The VIC-20's RAM as xvic 3.10 saves it, VIC20MEM 1.1: a byte of
        # the expansion blocks that hold RAM (bit 0 the 3K at $0400, bits
        # 1-3 BLK1-BLK3, bit 5 BLK5), the bytes the CPU's and the VIC's
        # data lines last held, a byte badline doesn't model (0, 1 or 6 in
        # xvic's snapshots, not following the blocks), then the RAM: $0000-$03FF, $1000-$1FFF, the 3K at
        # $0400-$0FFF, and BLK1, BLK2, BLK3 and BLK5 in turn, each only if
        # it holds RAM. The layout was inferred from xvic's snapshots of
        # each -memory setting, with each block filled with a byte of its
        # own and the data lines left at a byte the monitor wrote. Colour
        # RAM is in the VIC-I's module (VICI).
        #
        # Written and read: the RAM and both data lines' bytes. The fourth
        # byte is written as 0, and not read.
        module Mem
          NAME = "VIC20MEM"
          MAJOR = 1
          MINOR = 1
          # Each expansion block's bit in the first byte, and the bytes it
          # holds, as Badline::Vic20::Bus::BLOCKS names them.
          BLOCK_BITS = { ram123: 0x01, blk1: 0x02, blk2: 0x04, blk3: 0x08, blk5: 0x20 }.freeze
          INTERNAL = [[0x0000, 0x0400], [0x1000, 0x1000]].freeze

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          # The blocks the first byte names, or nil for bits no block has.
          def blocks(section)
            bits = FieldReader.new(section).byte
            names = BLOCK_BITS.select { |_, bit| bits.anybits?(bit) }.keys
            names.sum { |name| BLOCK_BITS[name] } == bits ? names : nil
          end

          # The RAM configuration (Badline::Vic20::Bus::RAM_CONFIGURATIONS)
          # whose blocks the module has, or nil.
          def ram_configuration(section)
            names = blocks(section)
            return nil if names.nil?

            Badline::Vic20::Bus::RAM_CONFIGURATIONS.find { |_, blocks| blocks.sort == names.sort }&.first
          end

          # The regions the RAM comes in, as [address, length].
          def regions(names)
            INTERNAL + Badline::Vic20::Bus::BLOCKS.filter_map do |name, (page, pages)|
              [page << 8, pages << 8] if names.include?(name)
            end
          end

          # The module for `machine`, with the data lines' bytes from its
          # BL-MACHINE fields, `machine_fields`.
          def export(machine, machine_fields)
            names = Badline::Vic20::Bus::RAM_CONFIGURATIONS.fetch(machine.ram_configuration)
            fields = FieldWriter.new.byte(names.sum { |name| BLOCK_BITS[name] })
            fields.byte(machine_fields.int("bus.data", 0)).byte(machine_fields.int("bus.video_data", 0))
            fields.byte(0)
            ram = machine.ram
            regions(names).each do |address, length|
              fields.bytes(Array.new(length) { |offset| ram.peek(address + offset) })
            end
            fields.section(NAME, MAJOR, MINOR)
          end

          # The RAM into `ram`, the machine's 48K at power-on, and the data
          # lines' bytes into BL-MACHINE's writer `out`.
          def import(section, ram, out)
            fields = FieldReader.new(section)
            names = blocks(section) || []
            fields.skip(1)
            out.int("bus.data", fields.byte).int("bus.video_data", fields.byte)
            fields.skip(1)
            regions(names).each { |address, length| ram[address, length] = fields.bytes(length) }
            ram
          end
        end
      end
    end
  end
end
