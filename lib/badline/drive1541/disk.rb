# frozen_string_literal: true

require "badline/drive1541/sector_reader"

module Badline
  class Drive1541
    # A disk as the head sees it: a Track for each half track that holds
    # data, numbered from 2 (track 1) to MAX_HALF_TRACK (track 42), and
    # nothing between them. A .d64 image fills the whole tracks; a .g64
    # can fill any of them.
    #
    # The head writes into the tracks' bytes, and a write to a half track
    # without data gives it a blank Track first. A disk made from an image
    # remembers it: flush reads the sectors back off the tracks written
    # since the last flush and stores them in the image, which writes its
    # host file. The disk is write-protected when the image won't take
    # writes.
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
        disk = new(image)
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

      attr_reader :image

      def initialize(image = nil)
        @image = image
        @tracks = Array.new(MAX_HALF_TRACK + 1)
        @written = {}
      end

      # The Track at the half track, or nil where there's no data.
      def track(half_track) = @tracks[half_track]

      def write(half_track, track)
        @tracks[half_track] = track
      end

      # Whether the write-protect notch is covered: the disk's image won't
      # take writes. A disk without an image takes them, and keeps them
      # only in its tracks.
      def write_protected? = !@image.nil? && !@image.writable?

      # A half track the head writes to, blank to begin with: no flux, and
      # as many bytes as a turn holds at the bit rate of the +zone+ it's
      # written in.
      def writable_track(half_track, zone)
        @tracks[half_track] ||= Track.new(Array.new(TRACK_LENGTHS[zone], 0), zone)
      end

      # The head wrote to the half track.
      def written(half_track)
        @written[half_track] = true
      end

      # Whether any track was written since the last flush.
      def written? = !@written.empty?

      # Reads the sectors of each track written since the last flush back
      # into the image, all in one write to its host file. The image keeps
      # its whole tracks only, so a half track, or a track past its last,
      # stays on the disk alone.
      def flush
        tracks = @written.keys.select { |half| half.even? && (1..@image&.track_count.to_i).cover?(half / 2) }
        @written.clear
        return if tracks.empty?

        sectors = tracks.to_h { |half| [half / 2, SectorReader.read(@tracks[half].bytes, half / 2)] }
        id = disk_id(sectors)
        @image.store_blocks(sectors.flat_map do |track, found|
          Array.new(@image.sectors_in(track)) { |sector| stored_block(track, sector, found[sector], id) }
        end)
      end

      private

      # The disk ID the headers must carry, from the header block's $A2 and
      # $A3 as Disk.from_d64 takes it: as just read back, or as the image
      # holds it.
      def disk_id(sectors)
        track, sector = @image.header_block
        header = sectors.dig(track, sector)&.data
        data = header ? header[1, 256] : @image.read_block(track, sector)
        [data[0xa2], data[0xa3]]
      end

      # [track, sector, data, error] for DiskImage#store_blocks: the data as
      # read, nil where it can't be, and the DOS error a read of it would
      # raise, the way Disk.from_d64 writes each one. A sector whose header
      # isn't found keeps its data, and reads as error 20, or 21 where the
      # image already has it so.
      def stored_block(track, sector, found, id)
        return [track, sector, nil, @image.block_error(track, sector) == 21 ? 21 : 20] unless found

        header = found.header
        data = found.data
        [track, sector, data && data[1, 256], block_error(header, data, id)]
      end

      def block_error(header, data, id)
        if header[1] != header[2] ^ header[3] ^ header[4] ^ header[5] then 27
        elsif header[5] != id[0] || header[4] != id[1] then 29
        elsif data.nil? || data[0] != DATA_ID then 22
        elsif data[257] != data[1, 256].reduce(:^) then 23
        end
      end
    end
  end
end
