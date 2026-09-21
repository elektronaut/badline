# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      SECTOR_SIZE = 256
      ENTRY_SIZE = 32
      ENTRIES_PER_SECTOR = 8
      FILETYPE_PRG = 0x02
      NAME_PADDING = 0xa0

      def initialize(path)
        @bytes = File.binread(path).bytes
      end

      def read_file(name)
        pattern = Storage.matcher(name)
        entry = entries.find { |e| pattern.match?(e[:name]) }
        read_chain(entry[:track], entry[:sector]) if entry
      end

      # Raw block access for the DOS `U1` command. Returns nil for blocks
      # outside the image's geometry.
      def read_block(track, sector)
        return unless block?(track, sector)

        sector_at(track, sector)
      end

      private

      def block?(track, sector)
        return false unless track.between?(1, 255) &&
                            sector.between?(0, sectors_in(track) - 1)

        sector_offset(track, sector) + SECTOR_SIZE <= @bytes.length
      end

      def entries
        @entries ||= each_sector(directory_track, directory_sector)
                     .flat_map { |data| parse_entries(data) }
      end

      def parse_entries(data)
        (0...ENTRIES_PER_SECTOR).filter_map do |i|
          entry = data[i * ENTRY_SIZE, ENTRY_SIZE]
          next unless (entry[2] & 0x07) == FILETYPE_PRG

          { name: decode_name(entry[5, 16]),
            track: entry[3],
            sector: entry[4] }
        end
      end

      def decode_name(bytes)
        Storage.ascii(bytes.take_while { |b| b != NAME_PADDING }).downcase
      end

      def read_chain(track, sector)
        each_sector(track, sector).flat_map do |data|
          data[0].zero? ? data[2..data[1]] : data[2..]
        end
      end

      def each_sector(track, sector)
        return to_enum(:each_sector, track, sector) unless block_given?

        visited = {}
        while track != 0 && !visited[[track, sector]]
          visited[[track, sector]] = true
          data = sector_at(track, sector)
          yield data
          track, sector = data[0, 2]
        end
      end

      def sector_at(track, sector)
        @bytes[sector_offset(track, sector), SECTOR_SIZE]
      end

      def sector_offset(track, sector)
        ((1...track).sum { |t| sectors_in(t) } + sector) * SECTOR_SIZE
      end
    end
  end
end
