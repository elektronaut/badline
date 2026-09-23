# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      SECTOR_SIZE = 256
      ENTRY_SIZE = 32
      ENTRIES_PER_SECTOR = 8
      FILETYPES = { seq: 0x01, prg: 0x02, usr: 0x03 }.freeze
      NAME_PADDING = 0xa0

      def initialize(path)
        @bytes = File.binread(path).bytes
      end

      # A LOAD reads only PRG files. An OPEN names the type it wants, or
      # takes the first file of any type with a nil `type`.
      def read_file(name, type: :prg)
        pattern = Storage.matcher(name)
        entry = entries.find do |e|
          (type.nil? || e[:type] == type) && pattern.match?(e[:name])
        end
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
          type = FILETYPES.key(entry[2] & 0x07)
          next unless type

          { name: decode_name(entry[5, 16]),
            type:,
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
