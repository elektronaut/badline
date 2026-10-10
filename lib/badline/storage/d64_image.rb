# frozen_string_literal: true

module Badline
  module Storage
    class D64Image < DiskImage
      # Image sizes with an error table, mapped to its length: 35 tracks
      # (174848 bytes without one), 40 tracks (196608) and 42 tracks (205312)
      ERROR_TABLES = { 175_531 => 683, 197_376 => 768, 206_114 => 802 }.freeze

      # The tracks the image holds: 35, 40 or 42.
      def track_count
        blocks = @bytes.length / SECTOR_SIZE
        count = 0
        count += 1 while count < 42 && track_offset(count + 2) <= blocks
        count
      end

      # The sides of a disk the image's tracks fill.
      def sides = 1

      # The last track of each of the 1541's speed zones but the innermost,
      # from the outermost, zone 3, in: tracks 1-17, 18-24 and 25-30, and
      # zone 0 from 31 on.
      ZONE_LAST_TRACKS = [17, 24, 30].freeze

      # The sectors a track holds in each zone, by its number.
      ZONE_SECTORS = [17, 18, 19, 21].freeze

      # The speed zone a track is written in, 3 for the outermost.
      def self.zone(track)
        zone = 3
        zone -= 1 while zone.positive? && track > ZONE_LAST_TRACKS[3 - zone]
        zone
      end

      def sectors_in(track) = ZONE_SECTORS[D64Image.zone(track)]

      private

      def error_tables = ERROR_TABLES

      def header_name = 0x90
      def directory_track = 18
      def directory_sector = 1
      def directory_interleave = 3
      def interleave = 10
      def reserved_tracks = [18]

      # The BAM in the header block covers the 35 tracks of a standard
      # disk. The layouts that extend it to 40 tracks differ between DOS
      # versions, so the tracks past 35 stay unused.
      def bam_tracks = 1..35
      def bam_count(track) = [18, 0, 4 * track]
      def bam_bitmap(track) = [18, 0, (4 * track) + 1]
    end
  end
end
