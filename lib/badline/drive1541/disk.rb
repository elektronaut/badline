# frozen_string_literal: true

module Badline
  class Drive1541
    # A disk as the head sees it: a Track for each half track that holds
    # data, numbered from 2 (track 1) to MAX_HALF_TRACK (track 42), and
    # nothing between them. A .d64 image fills the whole tracks; a .g64
    # can fill any of them.
    class Disk
      MAX_HALF_TRACK = 84

      # GCR bytes around a track in each speed zone: 200 ms of rotation at
      # 300 rpm, in bytes of 32, 30, 28 and 26 µs.
      TRACK_LENGTHS = [6250, 6666, 7142, 7692].freeze

      # The speed zone each track is written in: 3 for the 21 sectors of
      # tracks 1-17, 2 for 18-24, 1 for 25-30 and 0 from 31 on.
      def self.zone(track)
        if track <= 17 then 3
        elsif track <= 24 then 2
        elsif track <= 30 then 1
        else 0
        end
      end

      SYNC_LENGTH = 5
      HEADER_GAP = 9
      GAP = 0x55
      HEADER_ID = 0x08
      DATA_ID = 0x07

      # A sector: SYNC, the 10-byte GCR header, the header gap, SYNC and
      # the 325-byte GCR data block. The gap after it takes up the rest.
      SECTOR_LENGTH = SYNC_LENGTH + 10 + HEADER_GAP + SYNC_LENGTH + 325

      # A disk formatted from a D64 image, each sector laid out as the DOS
      # formats it, with the disk ID from the header block. A block the
      # image's error table marks 20, 21, 22, 23, 27 or 29 is written the
      # way that DOS error would read. The table's other codes, 24, 25, 26
      # and 28, describe write or decoding faults the layout can't carry,
      # so their blocks are written good and read without an error.
      def self.from_d64(image)
        track, sector = image.header_block
        header = image.read_block(track, sector)
        id = [header[0xa2], header[0xa3]]
        disk = new
        (1..image.track_count).each do |track|
          disk.write(track * 2, Track.new(format_track(image, track, id), zone(track)))
        end
        disk
      end

      def self.format_track(image, track, id)
        sectors = image.sectors_in(track)
        length = TRACK_LENGTHS[zone(track)]
        gap = (length - (sectors * SECTOR_LENGTH)) / sectors
        bytes = []
        sectors.times do |sector|
          format_sector(bytes, image, track, sector, id)
          gap.times { bytes << GAP }
        end
        bytes << GAP while bytes.length < length
        bytes
      end

      # Error 21 leaves the block without SYNC marks, and 29 writes its
      # header with the wrong first ID byte.
      def self.format_sector(bytes, image, track, sector, id)
        error = image.block_error(track, sector)
        sync = error == 21 ? GAP : 0xff
        id = [id[0] ^ 0xff, id[1]] if error == 29
        SYNC_LENGTH.times { bytes << sync }
        bytes.concat(GCR.encode(header(track, sector, id, error)))
        HEADER_GAP.times { bytes << GAP }
        SYNC_LENGTH.times { bytes << sync }
        bytes.concat(GCR.encode(data_block(image.read_block(track, sector), error)))
      end

      # ID, checksum, sector, track, the second ID byte, the first and two
      # $0F fillers. Error 20 hides the block's ID and 27 spoils its
      # checksum.
      def self.header(track, sector, id, error)
        checksum = sector ^ track ^ id[1] ^ id[0]
        checksum ^= 0xff if error == 27
        [error == 20 ? 0x00 : HEADER_ID, checksum, sector, track, id[1], id[0], 0x0f, 0x0f]
      end

      # ID, 256 data bytes, their checksum and two $00 fillers. Error 22
      # hides the block's ID and 23 spoils its checksum.
      def self.data_block(data, error)
        checksum = 0
        data.each { |byte| checksum ^= byte }
        checksum ^= 0xff if error == 23
        block = [error == 22 ? 0x00 : DATA_ID]
        block.concat(data)
        block << checksum << 0x00 << 0x00
      end

      def initialize
        @tracks = Array.new(MAX_HALF_TRACK + 1)
      end

      # The Track at the half track, or nil where there's no data.
      def track(half_track) = @tracks[half_track]

      def write(half_track, track)
        @tracks[half_track] = track
      end
    end
  end
end
