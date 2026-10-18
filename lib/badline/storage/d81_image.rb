# frozen_string_literal: true

module Badline
  module Storage
    class D81Image < DiskImage
      ERROR_TABLES = { 822_400 => 3200 }.freeze

      private

      def error_tables = ERROR_TABLES

      def header_name = 0x04
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
      def bitmap_size = 5

      # The header links the directory's first block, at 40/3. Each BAM
      # block links the next, names the format and its complement, and
      # holds the ID and the I/O byte.
      def header_link = [40, 3]
      def dos_type = "3D"
      def header_tail = 2

      def bam_headers(id)
        [[40, 1, [40, 2]], [40, 2, [0, 0xff]]].map do |track, sector, link|
          [track, sector, [*link, 0x44, 0xbb, *id, 0xc0, 0]]
        end
      end

      def sectors_in(_track) = 40
    end
  end
end
