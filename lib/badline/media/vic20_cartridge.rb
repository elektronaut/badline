# frozen_string_literal: true

module Badline
  module Media
    # A VIC-20 cartridge kept as programs, one per ROM chip, each loading
    # at the block the chip goes in. The chip in BLK5 at $A000 starts the
    # cartridge, and a bigger cartridge has more in BLK1 to BLK3. The files
    # of one cartridge share a name, with each block's address in its
    # extension (game.a0, game.60) or its name (game-a000.prg,
    # game-6000.prg).
    module Vic20Cartridge
      BLOCKS = [0xa000, 0x2000, 0x4000, 0x6000].freeze

      class << self
        # The ROM chips, as CRTFile::Chips, of the cartridge `data`, the
        # program at `path`, is a part of, or nil when it isn't one: a
        # program loading at $A000, or one loading at the start of BLK1 to
        # BLK3 with an $A000 part beside it.
        def chips(path, data)
          own = load_address(data)
          return unless BLOCKS.include?(own)

          parts = BLOCKS.filter_map { |address| address == own ? data : part(path, own, address) }
          return unless parts.any? { |part| load_address(part) == 0xa000 }

          parts.map { |part| rom_chip(part) }
        end

        # A program's bytes, unwrapped from a .p00.
        def program_bytes(path)
          bytes = File.binread(path).bytes
          Storage::P00.wraps?(bytes) ? Storage::P00.data(bytes) : bytes
        end

        private

        def load_address(data)
          data[0] | (data[1] << 8) if data.length > 2
        end

        def part(path, own, address)
          name = part_names(path, own, address).find { |candidate| File.file?(candidate) }
          return unless name

          part = program_bytes(name)
          part if load_address(part) == address
        end

        # `path` with the block at `own` in its extension or its name
        # swapped for the one at `address`, its letters in either case.
        def part_names(path, own, address)
          extension = File.extname(path)
          base = path[0, path.length - extension.length]
          own_tag = own.to_s(16)
          tags = [address.to_s(16), address.to_s(16).upcase].uniq
          return tags.map { |tag| "#{base}.#{tag[0, 2]}" } if extension.downcase == ".#{own_tag[0, 2]}"

          name = File.basename(base)
          at = name.downcase.index(own_tag)
          return [] unless at

          tags.map { |tag| File.join(File.dirname(base), name[0, at] + tag + name[(at + 4)..]) + extension }
        end

        # A ROM chip of whole pages, the last padded with $FF.
        def rom_chip(part)
          data = part[2..]
          data += [0xff] * (-data.length % 0x100)
          Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: load_address(part), data:)
        end
      end
    end
  end
end
