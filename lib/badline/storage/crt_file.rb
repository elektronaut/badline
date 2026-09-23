# frozen_string_literal: true

module Badline
  module Storage
    class CRTFile
      class FormatError < StandardError; end

      SIGNATURE = "C64 CARTRIDGE   ".b
      CHIP_SIGNATURE = "CHIP".b
      CHIP_HEADER_SIZE = 0x10
      RAM_CHIP = 1

      Chip = Data.define(:chip_type, :bank, :address, :data)

      attr_reader :hardware_type, :subtype, :exrom, :game, :name, :chips

      def initialize(path)
        parse(File.binread(path))
      end

      private

      def parse(bytes)
        raise FormatError, "Missing CRT signature" unless bytes.start_with?(SIGNATURE)

        @hardware_type = bytes[0x16, 2].unpack1("n")
        @exrom = bytes.getbyte(0x18)
        @game = bytes.getbyte(0x19)
        @subtype = bytes.getbyte(0x1a)
        @name = bytes[0x20, 32].unpack1("Z*")
        @chips = parse_chips(bytes, bytes[0x10, 4].unpack1("N"))
      end

      # Trailing bytes too short to hold a CHIP header are ignored.
      def parse_chips(bytes, offset)
        chips = []
        while offset + CHIP_HEADER_SIZE <= bytes.length
          chip, offset = parse_chip(bytes, offset)
          chips << chip
        end
        chips
      end

      def parse_chip(bytes, offset)
        raise FormatError, "Bad CHIP packet at offset #{offset}" unless bytes[offset, 4] == CHIP_SIGNATURE

        packet_length = bytes[offset + 4, 4].unpack1("N")
        chip_type, bank, address, size = bytes[offset + 8, 8].unpack("n4")
        data = chip_type == RAM_CHIP ? [] : bytes[offset + CHIP_HEADER_SIZE, size].bytes
        [Chip.new(chip_type:, bank:, address:, data:),
         offset + [packet_length, CHIP_HEADER_SIZE + data.length].max]
      end
    end
  end
end
