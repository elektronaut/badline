# frozen_string_literal: true

module Badline
  module Storage
    # A host directory served as a drive: .prg files by their host name,
    # .p00 and .t64 entries by their embedded names. A host file that can't
    # be read is left out, and a failed write reports false.
    class HostDirectory
      def initialize(path)
        @path = path
      end

      def read_file(name, **)
        entry = find(name)
        return unless entry

        archive = entry[:archive]
        archive ? archive.read_file(entry[:name]) : file_bytes(entry[:file])
      end

      def write_file(name, bytes)
        host_name = "#{name.downcase.tr('/', '_')}.prg"
        File.binwrite(File.join(@path, host_name), bytes.pack("C*"))
        true
      rescue SystemCallError
        false
      end

      private

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
        archive.names.map { |name| { name:, archive: } }
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
