# frozen_string_literal: true

require "badline/storage/p00"
require "badline/storage/host_directory"
require "badline/storage/disk_image"
require "badline/storage/d64_image"
require "badline/storage/d71_image"
require "badline/storage/d81_image"
require "badline/storage/t64"
require "badline/storage/crt_file"
require "badline/storage/sid_file"

module Badline
  module Storage
    class << self
      # Folds shifted PETSCII letters to their ASCII equivalents.
      def ascii(bytes)
        bytes.map { |b| b.between?(0xc1, 0xda) ? b - 0x80 : b }.pack("C*")
      end

      # CBM DOS drive prefix: "0:NAME" selects a drive, "@0:NAME" is
      # save-with-replace
      def strip_drive_prefix(name)
        name.sub(/\A@?\d*:/, "")
      end

      # CBM-style filename pattern: "*" and "?" wildcards, case-insensitive.
      def matcher(name)
        escaped = Regexp.escape(name.downcase)
                        .gsub('\*', ".*")
                        .gsub('\?', ".")
        Regexp.new("\\A#{escaped}\\z")
      end
    end
  end
end
