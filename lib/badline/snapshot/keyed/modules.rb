# frozen_string_literal: true

module Badline
  module Snapshot
    module Keyed
      # A snapshot's BL-* modules by name, which a family reads in its own
      # fixed order, whatever order the file has them in. Each module is
      # parsed once, and its Reader kept for the Report.
      #
      # A `detached` load restores a machine that opens no host file and
      # writes none: a disk image comes from the bytes the snapshot holds,
      # write-protected, and a directory device 8 serves is left out.
      class Modules
        attr_reader :readers

        def initialize(sections, detached: false)
          @sections = {}
          sections.each { |section| @sections[section.name] = section }
          @parsed = {}
          @readers = []
          @detached = detached
        end

        def detached? = @detached

        # BL-MACHINE, which every family writes first.
        def machine = required("BL-MACHINE")

        # The module a family always writes, or a Reader standing in for it,
        # reported missing.
        def required(name)
          reader = @parsed[name]
          return reader if reader

          section = @sections[name]
          keep(name, section.nil? ? missing(name) : parse(section))
        end

        # The module, or nil when the snapshot has none, as it has none for a
        # cartridge or a drive that isn't there.
        def optional(name)
          reader = @parsed[name]
          return reader if reader

          section = @sections[name]
          section.nil? ? nil : keep(name, parse(section))
        end

        # The BL-* modules no family read, from a later badline.
        def unread = @sections.keys.select { |name| name.start_with?("BL-") && !@parsed.key?(name) }

        private

        def parse(section) = Reader.parse(section)

        def missing(name) = Reader.missing(name)

        def keep(name, reader)
          @parsed[name] = reader
          @readers << reader
          reader
        end
      end
    end
  end
end
