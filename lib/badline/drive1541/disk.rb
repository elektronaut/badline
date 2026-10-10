# frozen_string_literal: true

require "badline/drive1541/sector_reader"
require "badline/drive1541/disk/saved_state"

module Badline
  class Drive1541
    # A disk as the head sees it: a Track for each half track that holds
    # data, numbered from 2 (track 1) to MAX_HALF_TRACK (track 42), and
    # nothing between them. A .d64 image fills the whole tracks; a .g64
    # can fill any of them, with tracks of any length.
    #
    # The disk has a second side, for the 1571's second head, its half
    # tracks numbered from SIDE on. A .d71 fills both sides, its tracks
    # 36-70 being tracks 1-35 of the second, and a .g71 holds 84 half
    # tracks a side. A 1541 reads the first side only.
    #
    # The head writes into the tracks' bytes, and a write to a half track
    # without data gives it a blank Track first. A disk made from an image
    # remembers it: flush reads the sectors back off the tracks written
    # since the last flush and stores them in the image, which writes its
    # host file. The disk is write-protected when the image won't take
    # writes.
    class Disk
      include SavedState

      MAX_HALF_TRACK = 84

      # Where the second side's half tracks start: its track 1 is SIDE + 2.
      SIDE = MAX_HALF_TRACK + 1

      # The tracks a side of a .d71 holds.
      D71_SIDE_TRACKS = 35

      # The half track entries a side of a .g71 holds.
      G71_SIDE_ENTRIES = 84

      # GCR bytes around a track in each speed zone (Storage::D64Image.zone):
      # 200 ms of rotation at 300 rpm, in bytes of 32, 30, 28 and 26 µs.
      TRACK_LENGTHS = [6250, 6666, 7142, 7692].freeze

      # How far round the DOS's N: starts each track from the one before,
      # in each zone, in 1/10000 of a turn: it steps in and starts writing
      # the next track that long after it started the last.
      SKEWS = [2916, 897, 8915, 6869].freeze
      SKEW_TURN = 10_000

      SYNC_LENGTH = 5
      HEADER_GAP = 9
      GAP = 0x55
      HEADER_ID = 0x08
      DATA_ID = 0x07

      # A sector: SYNC, the 10-byte GCR header, the header gap, SYNC and
      # the 325-byte GCR data block. The gap after it takes up the rest.
      SECTOR_LENGTH = SYNC_LENGTH + 10 + HEADER_GAP + SYNC_LENGTH + 325

      # A disk from the image at +path+: a .g64 or .g71 as its tracks are,
      # a .d71 formatted on both sides, and anything else as a .d64,
      # formatted. `read_only` opens the image write-protected.
      def self.open(path, read_only: false)
        image = image_for(path, read_only)
        (SavedState.g64?(path) ? from_g64(image) : from_d64(image)).opened(path, read_only)
      end

      # The image at +path+, by its name: a .g64 or .g71, a .d71, and
      # anything else a .d64.
      def self.image_for(path, read_only)
        return Storage::G64Image.new(path, read_only:) if SavedState.g64?(path)
        return Storage::D71Image.new(path, read_only:) if File.extname(path).casecmp?(".d71")

        Storage::D64Image.new(path, read_only:)
      end

      # A disk from a G64 or G71 image, each half track as the image stores
      # it, with its speed map. Flushing it writes the tracks back as they
      # are.
      def self.from_g64(image)
        disk = new(image)
        image.half_tracks.times do |entry|
          track = image.track(entry)
          disk.write(half_track_of(entry), Track.new(*track, image.speeds(entry))) if track
        end
        disk
      end

      # The half track a G64 or G71 table entry holds: entry 0 is track 1,
      # and a .g71's entries from G71_SIDE_ENTRIES on are the second
      # side's.
      def self.half_track_of(entry)
        side = entry / G71_SIDE_ENTRIES
        (side * SIDE) + (entry % G71_SIDE_ENTRIES) + Mechanism::MIN_HALF_TRACK
      end

      # The table entry of a half track, or nil for one a G64 or G71 has
      # no entry for.
      def self.entry_of(half_track)
        side = half_track / SIDE
        entry = (half_track % SIDE) - Mechanism::MIN_HALF_TRACK
        (side * G71_SIDE_ENTRIES) + entry if entry.between?(0, G71_SIDE_ENTRIES - 1)
      end

      # The half track an image's track number is on: a .d71's tracks past
      # D71_SIDE_TRACKS are on the second side.
      def self.d64_half_track(image, track)
        return track * 2 unless image.sides == 2 && track > D71_SIDE_TRACKS

        SIDE + ((track - D71_SIDE_TRACKS) * 2)
      end

      # The image's track number a half track holds, or nil for a half
      # track or one past the image's last.
      def self.d64_track(image, half_track)
        side = half_track / SIDE
        return unless (half_track % SIDE).even?

        track = (half_track % SIDE) / 2
        track += D71_SIDE_TRACKS if side == 1
        track if track.positive? && track <= image.track_count && side < image.sides
      end

      # A disk formatted from a D64 image, each sector laid out as the DOS
      # formats it, with the disk ID from the header block. A block the
      # image's error table marks 20, 21, 22, 23, 27 or 29 is written the
      # way that DOS error would read. The table's other codes, 24, 25, 26
      # and 28, describe write or decoding faults the layout can't carry,
      # so their blocks are written good and read without an error.
      #
      # Each track starts sector 0 at the angle the DOS's N: leaves it: track
      # 1 at the index angle, and each track after it SKEWS[zone] of a turn
      # round from the last. A .d71's second side starts over at the index
      # angle.
      def self.from_d64(image)
        track, sector = image.header_block
        header = image.read_block(track, sector)
        id = [header[0xa2], header[0xa3]]
        disk = new(image)
        angle = 0
        (1..image.track_count).each do |track|
          half_track = d64_half_track(image, track)
          zone = Storage::D64Image.zone((half_track % SIDE) / 2)
          angle = half_track == SIDE + 2 ? 0 : (angle + SKEWS[zone]) % SKEW_TURN if track > 1
          bytes = format_track(image, track, id, zone)
          disk.write(half_track, Track.new(bytes.rotate(-(bytes.length * angle / SKEW_TURN)), zone))
        end
        disk
      end

      def self.format_track(image, track, id, zone = Storage::D64Image.zone(track))
        sectors = image.sectors_in(track)
        length = TRACK_LENGTHS[zone]
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
        @tracks = Array.new(SIDE * 2)
        @written = {}
        @path = nil
        @read_only = false
      end

      # The Track at the half track, or nil where there's no data.
      def track(half_track) = @tracks[half_track]

      def write(half_track, track)
        @tracks[half_track] = track
      end

      # Whether the write-protect notch is covered: the disk's image won't
      # take writes, or a disk without an image was opened read-only. A
      # disk without an image keeps what it takes only in its tracks.
      def write_protected? = @image.nil? ? @read_only : !@image.writable?

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

      # Stores each track written since the last flush in the image, all
      # in one write to its host file. A G64 image takes the tracks as they
      # are. A D64 image takes the sectors read back off them, and keeps
      # whole tracks only, so a half track, or a track past its last, stays
      # on the disk alone. A sector that no longer reads back keeps its old
      # data, and the flush warns once, naming the tracks that lost one.
      def flush
        return flush_tracks if @image.respond_to?(:store_tracks)

        tracks = @written.keys.filter_map do |half|
          track = @image && Disk.d64_track(@image, half)
          [half, track] if track
        end
        @written.clear
        return if tracks.empty?

        sectors = tracks.to_h { |half, track| [track, SectorReader.read(@tracks[half].bytes, track)] }
        id = disk_id(sectors)
        warn_lost(sectors)
        @image.store_blocks(sectors.flat_map do |track, found|
          Array.new(@image.sectors_in(track)) { |sector| stored_block(track, sector, found[sector], id) }
        end)
      end

      private

      def flush_tracks
        tracks = @written.keys.sort.filter_map do |half|
          entry = Disk.entry_of(half)
          [entry, [@tracks[half].bytes, @tracks[half].zone]] if entry
        end.to_h
        @written.clear
        @image.store_tracks(tracks) unless tracks.empty?
      end

      def warn_lost(sectors)
        lost = sectors.keys.select do |track|
          Array.new(@image.sectors_in(track)) { |sector| lost?(track, sector, sectors[track][sector]) }.any?
        end
        return if lost.empty?

        warn "1541: tracks written that no longer read back whole: #{lost.join(', ')}. The .d64 keeps the old " \
             "data of the sectors lost, and a .g64 image keeps tracks as the drive writes them."
      end

      # A sector the head no longer finds, which the image doesn't already
      # hold as unreadable.
      def lost?(track, sector, found)
        found.nil? && ![20, 21].include?(@image.block_error(track, sector))
      end

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
