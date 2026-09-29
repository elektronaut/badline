# frozen_string_literal: true

module Badline
  module Storage
    # A directory as a 1541 sends it for LOAD"$",8: a BASIC program loaded
    # at $0401. The header line is line 0, the disk's name and ID in
    # reverse video, the name quoted. Each file is a line numbered by its
    # length in blocks, with the name quoted and padded to 16 characters,
    # then the type, marked `*` when the file was never closed and `<` when
    # it is locked. The last line numbers the free blocks. Lines are
    # padded with spaces to the drive's fixed widths, 27 characters for a
    # file and 25 for the others, and shifted spaces print as plain ones.
    #
    # Names come as the bytes on the disk, padded with shifted spaces to 16.
    # A file's name ends at its first shifted space, where the closing
    # quote goes, and whatever follows it in the entry shows after the
    # quote, as it does on a 1541.
    class Listing
      LOAD_ADDRESS = 0x0401
      NAME_LENGTH = 16
      NAME_PADDING = 0xa0
      SPACE = 0x20
      QUOTE = 0x22
      REVERSE_ON = 0x12
      FILE_WIDTH = 27
      WIDTH = 25
      TYPES = %w[DEL SEQ PRG USR REL CBM].freeze
      PRG = 2

      # One directory entry: its name's bytes, its type code (0 DEL to
      # 4 REL, and the 1581's 5 CBM), its length in blocks, and whether it
      # was closed and is locked.
      Entry = Data.define(:name, :type, :blocks, :closed, :locked)

      attr_reader :name, :id, :entries, :blocks_free

      def initialize(name:, id:, entries:, blocks_free:)
        @name = name
        @id = id
        @entries = entries
        @blocks_free = blocks_free
      end

      # Name bytes padded with shifted spaces, from ASCII text in upper
      # case, as a host file's name is listed.
      def self.encode(text)
        bytes = text.upcase.bytes.first(NAME_LENGTH)
        bytes + Array.new(NAME_LENGTH - bytes.length, NAME_PADDING)
      end

      # A host file listed as a closed PRG, named in ASCII, of the blocks
      # its bytes would take on a disk, 254 to a block.
      def self.program(name, length)
        Entry.new(name: encode(name), type: PRG, blocks: (length + 253) / 254, closed: true, locked: false)
      end

      # The file's bytes, load address first. A `$:NAME` or `$0:A*,B*`
      # pattern lists only the files that match one of its names.
      def bytes(request = "$")
        lines = [[0, padded(header, WIDTH)]]
        lines.concat(listed(request).map { |entry| [entry.blocks, file_line(entry)] })
        lines << [@blocks_free, padded("BLOCKS FREE.".bytes, WIDTH)]
        program(lines)
      end

      private

      def listed(request)
        patterns = request.sub(/\A\$\d*/, "")
        return @entries unless patterns.start_with?(":")

        matchers = patterns[1..].split(",").map { |pattern| Storage.matcher(pattern) }
        @entries.select do |entry|
          name = Storage.ascii(entry.name.take_while { |byte| byte != NAME_PADDING }).downcase
          matchers.any? { |matcher| matcher.match?(name) }
        end
      end

      def header
        [REVERSE_ON, QUOTE, *spaced(@name.first(NAME_LENGTH)), QUOTE, SPACE, *spaced(@id.first(5))]
      end

      # A block count under 10 or 100 takes more spaces before the name, so
      # the names line up.
      def file_line(entry)
        indent = 1 + (entry.blocks < 100 ? 1 : 0) + (entry.blocks < 10 ? 1 : 0)
        line = Array.new(indent, SPACE) + quoted(entry.name) + [entry.closed ? SPACE : "*".ord]
        line.concat(TYPES.fetch(entry.type, "???").bytes)
        line << (entry.locked ? "<".ord : SPACE)
        padded(line, FILE_WIDTH)
      end

      # The closing quote takes the first shifted space's place, or follows
      # a name that fills all 16.
      def quoted(name)
        name = name.first(NAME_LENGTH)
        name += Array.new(NAME_LENGTH - name.length, NAME_PADDING)
        cut = name.index(NAME_PADDING)
        name = cut ? [*name[0, cut], QUOTE, *name[(cut + 1)..], SPACE] : [*name, QUOTE]
        [QUOTE, *spaced(name)]
      end

      def padded(line, width) = line + Array.new([width - line.length, 0].max, SPACE)

      def spaced(bytes) = bytes.map { |byte| byte == NAME_PADDING ? SPACE : byte }

      def program(lines)
        address = LOAD_ADDRESS
        bytes = [address & 0xff, address >> 8]
        lines.each do |number, text|
          address += text.length + 5
          bytes.push(address & 0xff, address >> 8, number & 0xff, (number >> 8) & 0xff, *text, 0)
        end
        bytes.push(0, 0)
      end
    end
  end
end
