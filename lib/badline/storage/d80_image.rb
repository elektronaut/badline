# frozen_string_literal: true

module Badline
  module Storage
    # An 8050 disk: 77 tracks on one side, in four speed zones.
    class D80Image < DiskImage
      ERROR_TABLES = { 535_331 => 2083 }.freeze

      # The last track of each zone but the innermost, from the outermost
      # in: tracks 1-39, 40-53 and 54-64, and the last zone from 65 on.
      ZONE_LAST_TRACKS = [39, 53, 64].freeze

      # The sectors a track holds in each zone, from the outermost in.
      ZONE_SECTORS = [29, 27, 25, 23].freeze

      # The tracks a side holds.
      SIDE_TRACKS = 77

      def sectors_in(track)
        zone = ZONE_LAST_TRACKS.count { |last| track > last }
        ZONE_SECTORS[zone]
      end

      private

      def error_tables = ERROR_TABLES

      # The header block holds the disk name at $06 and the ID at $18,
      # after the link to the BAM's first block and the format, "C".
      def header_name = 0x06
      def directory_track = 39
      def directory_sector = 1
      def directory_interleave = 3
      def interleave = 6

      # Only the directory track is kept from files. The BAM's blocks on
      # track 38 are marked in use, and the rest of that track holds files.
      def reserved_tracks = [39]

      # The BAM takes blocks 0, 3, 6 and 9 of track 38 as it needs them,
      # each covering 50 tracks with a free count and a four-byte bitmap
      # each from offset 6.
      def bam_tracks = 1..SIDE_TRACKS
      def bam_count(track) = [38, 3 * ((track - 1) / 50), 6 + (5 * ((track - 1) % 50))]
      def bam_bitmap(track) = [38, 3 * ((track - 1) / 50), 7 + (5 * ((track - 1) % 50))]
    end
  end
end
