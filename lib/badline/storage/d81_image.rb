# frozen_string_literal: true

module Badline
  module Storage
    class D81Image < DiskImage
      ERROR_TABLES = { 822_400 => 3200 }.freeze

      private

      def error_tables = ERROR_TABLES

      def directory_track = 40
      def directory_sector = 3
      def directory_interleave = 1
      def interleave = 1
      def reserved_tracks = [40]

      # Blocks 1 and 2 of track 40 hold the BAM for tracks 1 to 40 and 41
      # to 80, six bytes a track from offset 16.
      def bam_tracks = 1..80
      def bam_count(track) = [40, track > 40 ? 2 : 1, 0x10 + (((track - 1) % 40) * 6)]
      def bam_bitmap(track) = [40, track > 40 ? 2 : 1, 0x11 + (((track - 1) % 40) * 6)]

      def sectors_in(_track) = 40
    end
  end
end
