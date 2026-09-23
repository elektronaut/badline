# frozen_string_literal: true

module Badline
  module Storage
    class D71Image < D64Image
      ERROR_TABLES = { 351_062 => 1366 }.freeze

      private

      def error_tables = ERROR_TABLES

      def sectors_in(track)
        track > 35 ? super(track - 35) : super
      end
    end
  end
end
