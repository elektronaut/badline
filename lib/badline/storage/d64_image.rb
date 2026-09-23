# frozen_string_literal: true

module Badline
  module Storage
    class D64Image < DiskImage
      # Image sizes with an error table, mapped to its length: 35 tracks
      # (174848 bytes without one), 40 tracks (196608) and 42 tracks (205312)
      ERROR_TABLES = { 175_531 => 683, 197_376 => 768, 206_114 => 802 }.freeze

      private

      def error_tables = ERROR_TABLES

      def directory_track = 18
      def directory_sector = 1

      def sectors_in(track)
        case track
        when 1..17 then 21
        when 18..24 then 19
        when 25..30 then 18
        else 17
        end
      end
    end
  end
end
