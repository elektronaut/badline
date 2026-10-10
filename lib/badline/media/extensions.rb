# frozen_string_literal: true

module Badline
  module Media
    # The kind of medium each file extension names, which every check of a
    # path's extension reads. A file with any other extension is a program.
    # It loads on its own, for Options.
    #
    # - :disk, a disk image that the traps mount and a true drive reads
    # - :gcr, a disk's raw GCR, which only a true drive reads
    # - :archive, a .t64, which the traps mount read-only
    # - :tape, :cartridge and :tune
    # - :disk_list, a list of the disks of a set (DiskList)
    module Extensions
      KINDS = {
        ".d64" => :disk, ".d71" => :disk, ".d81" => :disk, ".g64" => :gcr, ".g71" => :gcr, ".t64" => :archive,
        ".tap" => :tape, ".crt" => :cartridge, ".sid" => :tune, ".m3u" => :disk_list, ".vfl" => :disk_list
      }.freeze

      # The kind of the medium at `path`, by its extension.
      def self.kind(path) = KINDS.fetch(File.extname(path).downcase, :program)

      # The extensions of the kinds given.
      def self.of(kinds) = KINDS.keys.select { |extension| kinds.include?(KINDS[extension]) }.freeze

      # Disk images, which a drive reads.
      DISKS = of(%i[disk gcr])

      # What goes in device 8 through the traps.
      MOUNTABLE = of(%i[disk archive])
    end
  end
end
