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

      def storage_kind = D64

      # The sides of a disk the image's tracks fill.
      def sides = 1

      def sectors_in(track)
        case track
        when 1..17 then 21
        when 18..24 then 19
        when 25..30 then 18
        else 17
        end
      end

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
