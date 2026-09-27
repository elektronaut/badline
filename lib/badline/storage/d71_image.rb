# frozen_string_literal: true

module Badline
  module Storage
    class D71Image < D64Image
      ERROR_TABLES = { 351_062 => 1366 }.freeze

      private

      def error_tables = ERROR_TABLES

      def interleave = 6
      def reserved_tracks = [18, 53]

      # The header block flags a double-sided disk. The second side's free
      # counts follow the first side's BAM there, and its bitmaps take the
      # first block of track 53.
      def bam_tracks = double_sided? ? 1..70 : super
      def bam_count(track) = track > 35 ? [18, 0, 0xdd + track - 36] : super
      def bam_bitmap(track) = track > 35 ? [53, 0, 3 * (track - 36)] : super

      def double_sided? = @bytes[sector_offset(18, 0) + 3].anybits?(0x80)

      def sectors_in(track)
        track > 35 ? super(track - 35) : super
      end
    end
  end
end
