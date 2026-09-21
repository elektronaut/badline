# frozen_string_literal: true

module Badline
  module Storage
    class T64
      class FormatError < StandardError; end

      SIGNATURE = "C64".bytes.freeze
      HEADER_SIZE = 0x40
      ENTRY_SIZE = 32
      NORMAL_FILE = 1

      def initialize(path)
        @bytes = File.binread(path).bytes
        raise FormatError, "Missing T64 signature" unless @bytes[0, 3] == SIGNATURE
      end

      def read_file(name)
        pattern = Storage.matcher(name)
        entry = entries.find { |e| pattern.match?(e[:name]) }
        return unless entry

        # Stated end addresses are frequently wrong; the slice stops at
        # the end of the archive either way.
        entry[:load] + (@bytes[entry[:offset], entry[:length]] || [])
      end

      def names
        entries.map { |e| e[:name] }
      end

      private

      def entries
        @entries ||= (0...entry_count).filter_map { |i| entry_at(i) }
      end

      # Directory size ($22) and used count ($24) disagree in the wild.
      def entry_count
        [word(0x22), word(0x24)].max
      end

      def entry_at(index)
        entry = @bytes[HEADER_SIZE + (index * ENTRY_SIZE), ENTRY_SIZE]
        return unless entry&.length == ENTRY_SIZE && entry[0] == NORMAL_FILE

        { name: decode_name(entry[16, 16]),
          load: entry[2, 2],
          offset: little_endian(entry[8, 4]),
          length: little_endian(entry[4, 2]) - little_endian(entry[2, 2]) }
      end

      # Names are padded with spaces, though NUL padding also occurs.
      def decode_name(bytes)
        Storage.ascii(bytes).downcase.sub(/[ \0]+\z/, "")
      end

      def word(offset)
        little_endian(@bytes[offset, 2])
      end

      def little_endian(bytes)
        bytes.each_with_index.sum { |byte, i| byte << (8 * i) }
      end
    end
  end
end
