# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      SECTOR_SIZE = 256
      ENTRY_SIZE = 32
      ENTRIES_PER_SECTOR = 8
      FILETYPES = { seq: 0x01, prg: 0x02, usr: 0x03 }.freeze
      NAME_PADDING = 0xa0

      # Error table codes and the DOS errors they stand for: 20 to 29 are
      # the read, write and ID errors, 74 is DRIVE NOT READY.
      DOS_ERRORS = (2..11).to_h { |code| [code, code + 18] }.merge(15 => 74).freeze

      def initialize(path)
        @bytes = File.binread(path).bytes
        @errors = split_error_table
      end

      # A LOAD reads only PRG files. An OPEN names the type it wants, or
      # takes the first file of any type with a nil `type`.
      def read_file(name, type: :prg)
        entry = find_entry(name, type)
        read_chain(entry[:track], entry[:sector]) if entry
      end

      # The first block in a file's chain that the error table marks bad:
      # its DOS error, its track and sector, and how many of the file's
      # bytes come before it. Nil when the whole chain reads cleanly.
      def read_error(name, type: :prg)
        entry = find_entry(name, type)
        return unless @errors && entry

        offset = 0
        each_sector(entry[:track], entry[:sector]) do |data, track, sector|
          error = block_error(track, sector)
          return { error:, track:, sector:, offset: } if error

          offset += data[0].zero? ? data[1] - 1 : SECTOR_SIZE - 2
        end
        nil
      end

      # The track and sector a file's chain starts at.
      def first_block(name, type: :prg)
        entry = find_entry(name, type)
        [entry[:track], entry[:sector]] if entry
      end

      # The bytes of the chain that starts at the block, or nil when the
      # block is outside the image's geometry.
      def read_file_at(track, sector)
        read_chain(track, sector) if block?(track, sector)
      end

      # The track and sector of the last block in a file's chain.
      def last_block(name, type: :prg)
        entry = find_entry(name, type)
        return unless entry

        last = nil
        each_sector(entry[:track], entry[:sector]) { |_data, track, sector| last = [track, sector] }
        last
      end

      # Raw block access for the DOS `U1` command. Returns nil for blocks
      # outside the image's geometry.
      def read_block(track, sector)
        return unless block?(track, sector)

        sector_at(track, sector)
      end

      # The DOS error a read of the block raises, from the error table an
      # image can carry after its last block, or nil when it reads cleanly.
      def block_error(track, sector)
        return unless @errors && block?(track, sector)

        DOS_ERRORS[@errors[track_offset(track) + sector]]
      end

      # The block holding the disk name and ID, at the start of the
      # directory track.
      def header_block = [directory_track, 0]

      # The directory block a new file's entry goes into: the first with a
      # free slot, or the last one when every slot is taken.
      def new_entry_block
        last = nil
        each_sector(directory_track, directory_sector) do |data, track, sector|
          return [track, sector] if (0...ENTRIES_PER_SECTOR).any? { |i| data[(i * ENTRY_SIZE) + 2].zero? }

          last = [track, sector]
        end
        last
      end

      private

      # An error table holds one byte per block after the last one. The image
      # sizes that carry one are listed exactly, since a 40-track D64 with a
      # table is also a whole number of 256-byte blocks.
      def split_error_table
        blocks = error_tables[@bytes.length]
        @bytes.pop(blocks) if blocks
      end

      def block?(track, sector)
        return false unless track.between?(1, 255) &&
                            sector.between?(0, sectors_in(track) - 1)

        sector_offset(track, sector) + SECTOR_SIZE <= @bytes.length
      end

      def find_entry(name, type)
        pattern = Storage.matcher(name)
        entries.find do |e|
          (type.nil? || e[:type] == type) && pattern.match?(e[:name])
        end
      end

      def entries
        @entries ||= begin
          list = []
          each_sector(directory_track, directory_sector) { |data| list.concat(parse_entries(data)) }
          list
        end
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
        bytes = []
        each_sector(track, sector) do |data|
          bytes.concat(data[0].zero? ? data[2..data[1]] : data[2..])
        end
        bytes
      end

      def each_sector(track, sector)
        visited = {}
        while track != 0 && !visited[[track, sector]]
          visited[[track, sector]] = true
          data = sector_at(track, sector)
          yield data, track, sector
          track, sector = data[0, 2]
        end
      end

      def sector_at(track, sector)
        @bytes[sector_offset(track, sector), SECTOR_SIZE]
      end

      def sector_offset(track, sector)
        (track_offset(track) + sector) * SECTOR_SIZE
      end

      def track_offset(track)
        (1...track).sum { |t| sectors_in(t) }
      end
    end
  end
end
