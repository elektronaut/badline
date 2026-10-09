# frozen_string_literal: true

module Badline
  class Drive1581
    # One side of a cylinder as the WD1772 finds it: its sectors, each an
    # ID field and a data field at a place round the turn, counted in
    # bytes from the index pulse. The disk turns at 300 rpm and the bits
    # pass at 250 kbit/s, so a turn is LENGTH bytes of 32 µs. The bytes
    # between the fields, the gaps and the sync marks, are not kept: a
    # read track lays them out again (raw).
    #
    # A standard track is the one the 1581 DOS formats (its format routine,
    # and the 1581 Service Manual's per-sector organization): 32 bytes of
    # $4E after the index, then ten 512-byte sectors numbered from 1, each
    #
    #   12 x $00, 3 x $A1, $FE, track, side, sector, size code, CRC,
    #   22 x $4E, 12 x $00, 3 x $A1, $FB, 512 data bytes, CRC,
    #   35 x $4E
    #
    # and $4E to the index. A write track lays down whatever the CPU sends,
    # and parse finds its fields again.
    class Track
      LENGTH = 6250
      GAP = 0x4e
      SYNC = 0xa1
      ID_MARK = 0xfe
      DATA_MARK = 0xfb
      DELETED_MARK = 0xf8

      SECTORS = 10
      SECTOR_SIZE = 512
      SIZE_CODE = 2

      # Where the first sector's ID mark lies, and how far apart the
      # sectors are.
      FIRST_ID = 32 + 15
      SECTOR_SPACING = 574 + 35

      # From an ID mark to its data mark.
      DATA_OFFSET = 44

      # How far after an ID field's CRC a data mark still belongs to it
      # (WD177x data sheet).
      DATA_MARK_WINDOW = 43

      # An ID or data field: its mark's place, its bytes, whether its CRC
      # reads back, and for a data field whether its mark is the deleted
      # one.
      Field = Struct.new(:mark, :bytes, :good, :deleted)

      # A sector: its ID field and its data field, or nil where none
      # follows the ID.
      Sector = Struct.new(:id, :data)

      # The CRC-CCITT the WD1772 writes after each field, over the field
      # from its first $A1: x^16 + x^12 + x^5 + 1 from $FFFF.
      def self.crc(bytes, crc = 0xffff)
        bytes.each do |byte|
          crc ^= byte << 8
          8.times { crc = crc.anybits?(0x8000) ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff }
        end
        crc
      end

      # A field's CRC as the two bytes written after it: the mark and
      # +bytes+, behind three $A1s.
      def self.field_crc(mark, bytes)
        crc = crc([SYNC, SYNC, SYNC, mark] + bytes)
        [crc >> 8, crc & 0xff]
      end

      # A standard track for +cylinder+ and +side+, each sector's data the
      # block yields for its number, 1 to 10.
      def self.standard(cylinder, side)
        sectors = Array.new(SECTORS) do |index|
          mark = FIRST_ID + (index * SECTOR_SPACING)
          id = Field.new(mark, [cylinder, side, index + 1, SIZE_CODE], true, false)
          Sector.new(id, Field.new(mark + DATA_OFFSET, yield(index + 1), true, false))
        end
        new(sectors)
      end

      attr_reader :sectors

      def initialize(sectors)
        @sectors = sectors
      end

      # The first sector whose ID mark lies at or after +position+, round
      # from the index if none does, or nil on a track without IDs.
      def next_id(position)
        @sectors.find { |sector| sector.id.mark >= position } || @sectors.first
      end

      # The sector with the ID field +id+, track, side, sector and size
      # code, or nil.
      def sector(id) = @sectors.find { |sector| sector.id.bytes == id }
    end
  end
end
