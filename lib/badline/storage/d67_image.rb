# frozen_string_literal: true

module Badline
  module Storage
    # A 2040's disk, as DOS 1 formats it: the 1541's 35 tracks and speed
    # zones, with 20 sectors on tracks 18 to 24 in place of 19, 690 blocks
    # in all. The BAM and the directory are where a 1541's are, on 18/0
    # and 18/1, but the BAM's format byte is $01 and the header has no DOS
    # type after the ID, as c1541 formats a .d67.
    class D67Image < DiskImage
      ERROR_TABLES = { 177_330 => 690 }.freeze

      # The sectors a track holds in each of the 1541's speed zones, by its
      # number, from zone 0, the innermost.
      ZONE_SECTORS = [17, 18, 20, 21].freeze

      # The tracks the image holds.
      def track_count = 35

      def sides = 1

      def sectors_in(track) = ZONE_SECTORS[D64Image.zone(track)]

      private

      def error_tables = ERROR_TABLES

      def header_name = 0x90
      def directory_track = 18
      def directory_sector = 1
      def directory_interleave = 3
      def interleave = 10
      def reserved_tracks = [18]

      def bam_tracks = 1..35
      def bam_count(track) = [18, 0, 4 * track]
      def bam_bitmap(track) = [18, 0, (4 * track) + 1]
      def bitmap_size = 3

      def header_link = [18, 1]
      def dos_type = "  "
      def header_tail = 5
      def bam_headers(_id) = []

      # The link to the directory, the format byte $01, and after the name
      # the ID and two spaces.
      def write_header(name, id)
        write_at(*header_block, 0, [*header_link, 0x01, 0])
        write_at(*header_block, header_name,
                 encode_name(name) + [NAME_PADDING, NAME_PADDING] + id + dos_type.bytes +
                 Array.new(header_tail, NAME_PADDING))
      end
    end
  end
end
