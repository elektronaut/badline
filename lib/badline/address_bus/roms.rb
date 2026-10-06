# frozen_string_literal: true

module Badline
  class AddressBus
    # The BASIC, character and KERNAL ROMs, and which KERNAL is fitted.
    module ROMs
      # The KERNAL ROMs a machine can be fitted with, by name: the C64's,
      # the SX-64's, the PET 64's and the C64GS's. The C64GS's is a 16K
      # image of its BASIC and its KERNAL, and fits both.
      KERNALS = {
        c64: "kernal.rom", sx64: "kernal-sx64.rom", pet64: "kernal-pet64.rom", gs: "c64gs.rom"
      }.freeze

      attr_reader :basic_rom, :character_rom, :kernal_rom, :kernal

      # Fits the KERNAL ROM KERNALS names `name`, in place of the one before,
      # with the BASIC of a 16K image or else the C64's.
      def kernal=(name)
        raise ArgumentError, "no KERNAL named #{name}" unless KERNALS.key?(name)

        @kernal = name
        data = ROM.read(KERNALS[name])
        basic = data.length == 0x4000 ? data[0, 0x2000] : ROM.read("basic.rom")
        @basic_rom = ROM.new(basic, length: 0x2000, start: 0xa000)
        @kernal_rom = ROM.new(data[-0x2000, 0x2000], length: 0x2000, start: 0xe000)
        update_overlays!
      end

      private

      def load_roms
        @basic_rom = ROM.load("basic.rom", 0xa000)
        @character_rom = ROM.load("character.rom", 0xd000)
        @kernal = :c64
        @kernal_rom = ROM.load(KERNALS[:c64], 0xe000)
      end
    end
  end
end
