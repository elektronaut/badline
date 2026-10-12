# frozen_string_literal: true

module Badline
  module Media
    # What the 264 series does with media of its own (Media.attach). A
    # cartridge is a PLUS4 CARTRIDGE .crt, or a raw ROM image (.bin) that
    # goes in the slot it's given, or by its size in cartridge 1's.
    module Plus4Media
      # The platform byte of a C16 or Plus/4 tape (Storage::TAP#platform).
      TAPE_PLATFORM = 2

      # The extension of a raw cartridge ROM image.
      ROM_IMAGE = ".bin"

      # The cartridge slots by xplus4's names, each as the bank and address
      # a .crt's CHIP packet gives it (Plus4::Bus#attach_cartridge).
      SLOTS = { "c1lo" => [0, 0x8000], "c1hi" => [0, 0xc000], "c2lo" => [1, 0x8000], "c2hi" => [1, 0xc000] }.freeze

      SLOT_SIZE = 0x4000

      class << self
        # A tape made for another machine plays all the same, and says so.
        def tape_message(tape, message)
          tape.platform == TAPE_PLATFORM ? message : "#{message}, a tape for another machine than the Plus/4"
        end

        # Whether the file at `path` is a raw cartridge ROM image.
        def rom_image?(path) = File.extname(path).downcase == ROM_IMAGE

        # The ROM chips, as Storage::CRTFile::Chips, of the cartridge at
        # `path`: a .crt's, or a raw image's (#rom_chips).
        def cartridge_chips(path, slot: nil)
          return rom_chips(File.binread(path).bytes, slot:) if rom_image?(path)

          Storage::CRTFile.new(path, machine: :plus4).chips
        end

        # A raw ROM image's chips: one in `slot`, one of SLOTS, when it's
        # named. Otherwise up to 16K goes in cartridge 1's low slot, and
        # up to 32K fills its high slot too.
        def rom_chips(bytes, slot: nil)
          return [slot_chip(bytes, slot)] if slot

          size = bytes.length
          unless size.between?(1, 2 * SLOT_SIZE)
            raise Machine::Unsupported, "a #{size}-byte image is no Plus/4 cartridge"
          end

          chips = [chip(0, 0x8000, bytes[0, SLOT_SIZE])]
          chips << chip(0, 0xc000, bytes[SLOT_SIZE..]) if size > SLOT_SIZE
          chips
        end

        private

        def slot_chip(bytes, slot)
          bank, address = SLOTS.fetch(slot) { raise ArgumentError, "no Plus/4 cartridge slot named #{slot}" }
          size = bytes.length
          raise Machine::Unsupported, "a #{size}-byte image doesn't fit a 16K slot" unless size.between?(1, SLOT_SIZE)

          chip(bank, address, bytes)
        end

        def chip(bank, address, data) = Storage::CRTFile::Chip.new(chip_type: 0, bank:, address:, data:)
      end
    end
  end
end
