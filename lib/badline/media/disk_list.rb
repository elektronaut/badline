# frozen_string_literal: true

module Badline
  module Media
    # A list of the disks of a set: an .m3u playlist, one path a line, or
    # a VICE .vfl flip list, whose paths follow a `UNIT 8` line. Paths are
    # relative to the list or absolute, and blank lines and lines starting
    # with # are skipped. Only the disk images the list names that are
    # there count.
    module DiskList
      # A list naming no disk image that's there.
      class Error < ArgumentError; end

      EXTENSIONS = %w[.m3u .vfl].freeze

      def self.list?(path) = EXTENSIONS.include?(File.extname(path).downcase)

      # The disk `path` puts in the drive: a list's first disk, or the
      # path itself.
      def self.disk(path)
        return path unless list?(path)

        disks = disks(path)
        raise Error, "#{path} lists no disk image that's there" if disks.empty?

        disks.first
      end

      # The disk images the list names that are there, in its order.
      def self.disks(list)
        directory = File.dirname(list)
        found = []
        entries(list).each do |entry|
          disk = entry.start_with?("/") ? entry : File.join(directory, entry)
          found << disk if DiskSet::EXTENSIONS.include?(File.extname(disk).downcase) && File.file?(disk)
        end
        found
      end

      # The paths of the list's lines, only unit 8's for a .vfl, which
      # starts on unit 8.
      def self.entries(list)
        flip = File.extname(list).casecmp?(".vfl")
        unit = true
        found = []
        File.foreach(list) do |line|
          text = line.strip
          next if text.empty? || text.start_with?("#")

          if flip && text.match?(/\AUNIT\s+\d+\z/i)
            unit = text.split.last.to_i == 8
          elsif unit
            found << text
          end
        end
        found
      rescue SystemCallError
        []
      end

      # The disks of the first list in the disk's folder that names it,
      # with the disk as given, or none.
      def self.beside(path)
        directory = File.dirname(path)
        own = File.expand_path(path)
        lists = DiskSet.children(directory).sort.select { |name| list?(name) }
        sets = lists.map { |name| disks(File.join(directory, name)) }
        set = sets.find { |listed| listed.any? { |disk| File.expand_path(disk) == own } }
        return [] if set.nil?

        set.map { |disk| File.expand_path(disk) == own ? path : disk }
      end
    end
  end
end
