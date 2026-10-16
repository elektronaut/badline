# frozen_string_literal: true

module Badline
  module Storage
    # An 8250 disk: an 8050's 77 tracks on each side, tracks 78-154 on the
    # second, one directory and one BAM for both.
    class D82Image < D80Image
      ERROR_TABLES = { 1_070_662 => 4166 }.freeze

      def sectors_in(track)
        track > SIDE_TRACKS ? super(track - SIDE_TRACKS) : super
      end

      private

      def error_tables = ERROR_TABLES

      def bam_tracks = 1..(2 * SIDE_TRACKS)
    end
  end
end
