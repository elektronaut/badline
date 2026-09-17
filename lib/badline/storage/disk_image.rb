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

      private

      def entries
        @entries ||= sector_chain(directory_track, directory_sector)
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
        sector_chain(track, sector).flat_map do |data|
          data[0].zero? ? data[2..data[1]] : data[2..]
        end
      end

      # Follows the sector chain from (track, sector) and returns the
      # sectors it visits. Returning the array rather than yielding keeps
      # this off `to_enum`, which an AOT compiler has no name to resolve.
      def sector_chain(track, sector)
        sectors = []
        visited = {}
        while track != 0 && !visited[[track, sector]]
          visited[[track, sector]] = true
          data = sector_at(track, sector)
          sectors << data
          track, sector = data[0, 2]
        end
        sectors
      end

      # Geometry hooks. Declared here so the base class carries the full
      # interface it calls into, rather than relying on the subclass that
      # happens to define it.
      def directory_track
        raise NotImplementedError
      end

      def directory_sector
        raise NotImplementedError
      end

      def sectors_in(_track)
        raise NotImplementedError
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
