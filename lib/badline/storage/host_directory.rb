# frozen_string_literal: true

module Badline
  module Storage
    # A host directory served as a drive: .prg files by their host name,
    # .p00 and .t64 entries by their embedded names. A .prg the host can't
    # read is still listed but fails to read, a .p00 or .t64 whose names
    # can't be read is left out, and a failed write reports false.
    class HostDirectory
      NO_SYNC = 21
      ID = "DIR".bytes.freeze

      # The directory's path, as it was opened.
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def read_file(name, **)
        entry = find(name)
        return unless entry

        archive = entry[:archive]
        archive ? archive.read_file(entry[:name]) : file_bytes(entry[:file]) || []
      end

      # A listed file the host can't read fails before its first byte, as
      # a 1541 does on a disk it finds no sync on.
      def read_error(name, **)
        entry = find(name)
        return unless entry && entry[:file] && !file_bytes(entry[:file])

        { error: NO_SYNC, track: 0, sector: 0, offset: 0 }
      end

      # Writes a .prg of any file type, over the one of the same name.
      def write_file(name, bytes, **)
        host_name = "#{name.downcase.tr('/', '_')}.prg"
        File.binwrite(File.join(@path, host_name), bytes.pack("C*"))
        true
      rescue SystemCallError
        false
      end

      # The directory as LOAD"$" lists it, under its host name: every file
      # as a PRG, of the blocks it would take on a disk. A host directory
      # counts no free blocks.
      def directory
        Listing.new(name: Listing.encode(File.basename(@path)), id: ID,
                    entries: entries.map { |entry| listing_entry(entry) }, blocks_free: 0)
      end

      private

      def listing_entry(entry)
        entry[:listed] || Listing.program(entry[:name], file_length(entry[:file]))
      end

      def file_length(file)
        size = File.size(File.join(@path, file))
        File.extname(file).casecmp?(".p00") ? size - P00::HEADER_SIZE : size
      rescue SystemCallError
        0
      end

      def find(name)
        pattern = Storage.matcher(name)
        entries.find { |e| pattern.match?(e[:name]) }
      end

      def entries
        Dir.children(@path).sort.flat_map { |f| entry_for(f) }.compact
      rescue SystemCallError
        []
      end

      def entry_for(file)
        case File.extname(file).downcase
        when ".prg"
          { name: File.basename(file, ".*").downcase, file: }
        when ".p00"
          p00_entry(file)
        when ".t64"
          t64_entries(file)
        end
      end

      def p00_entry(file)
        header = File.binread(File.join(@path, file), P00::HEADER_SIZE).bytes
        { name: P00.name(header), file: } if P00.wraps?(header)
      rescue SystemCallError
        nil
      end

      def t64_entries(file)
        archive = T64.new(File.join(@path, file))
        archive.names.zip(archive.listing_entries).map { |name, listed| { name:, archive:, listed: } }
      rescue T64::FormatError, SystemCallError
        nil
      end

      def file_bytes(file)
        bytes = File.binread(File.join(@path, file)).bytes
        P00.wraps?(bytes) ? P00.data(bytes) : bytes
      rescue SystemCallError
        nil
      end
    end
  end
end
