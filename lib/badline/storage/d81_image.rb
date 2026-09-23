# frozen_string_literal: true

module Badline
  module Storage
    class D81Image < DiskImage
      ERROR_TABLES = { 822_400 => 3200 }.freeze

      private

      def error_tables = ERROR_TABLES

      def directory_track = 40
      def directory_sector = 3

      def sectors_in(_track) = 40
    end
  end
end
