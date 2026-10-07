# frozen_string_literal: true

require "zlib"

module Badline
  module Snapshot
    # One module of a snapshot: its name, its version and its payload,
    # without the 22-byte module header.
    Section = Data.define(:name, :major, :minor, :data) do
      def version = "#{major}.#{minor}"

      def to_s = "#{name} #{version}"
    end

    # The .vsf container as the VICE manual describes it: a magic string,
    # the file format version and a machine name, an optional VICE version
    # block, then modules one after another, each a 16-byte name, a major
    # and minor version and a little-endian length that counts the header.
    # A gzipped file reads as the file inside it, as VICE's own does.
    class Container
      MAGIC = "VICE Snapshot File\x1a".b
      VERSION_MAGIC = "VICE Version\x1a".b
      NAME_LENGTH = 16
      MODULE_HEADER = NAME_LENGTH + 6
      FORMAT_MAJOR = 2
      FORMAT_MINOR = 0
      # x64sc names its machine C64SC, and refuses a snapshot naming another.
      MACHINE = "C64SC"
      # xvic names its machine VIC20.
      VIC20 = "VIC20"
      GZIP_MAGIC = "\x1f\x8b".b

      # The VICE version block, when VICE wrote the file: four version
      # bytes and a revision, kept as read.
      attr_reader :machine, :sections, :vice_version

      def self.parse(bytes)
        bytes = bytes.b
        bytes = gunzip(bytes) if bytes.start_with?(GZIP_MAGIC)
        raise FormatError, "not a VICE snapshot" unless bytes.start_with?(MAGIC)

        Reader.new(bytes).container
      end

      def self.gunzip(bytes)
        Zlib.gunzip(bytes).b
      rescue Zlib::Error => e
        raise FormatError, "the gzipped snapshot is damaged: #{e.message}"
      end

      def initialize(sections = [], machine: MACHINE, vice_version: nil)
        @machine = machine
        @sections = sections
        @vice_version = vice_version
      end

      def [](name) = @sections.find { |section| section.name == name }

      def to_s
        header = MAGIC + [FORMAT_MAJOR, FORMAT_MINOR].pack("CC") + padded(@machine)
        header += VERSION_MAGIC + @vice_version if @vice_version
        header + @sections.map { |section| encode(section) }.join
      end

      private

      def padded(name)
        raise ArgumentError, "#{name} is longer than #{NAME_LENGTH} bytes" if name.bytesize > NAME_LENGTH

        name.b.ljust(NAME_LENGTH, "\0")
      end

      def encode(section)
        padded(section.name) + [section.major, section.minor, MODULE_HEADER + section.data.bytesize].pack("CCV") +
          section.data.b
      end

      # Splits the bytes of a snapshot into its header and modules.
      class Reader
        def initialize(bytes)
          @bytes = bytes
          @pos = MAGIC.bytesize + 2
        end

        def container
          machine = take(NAME_LENGTH).delete("\0")
          version = vice_version
          sections = []
          sections << section while @pos < @bytes.bytesize
          Container.new(sections, machine:, vice_version: version)
        end

        private

        def take(length)
          raise FormatError, "snapshot ends early, at byte #{@bytes.bytesize}" if @pos + length > @bytes.bytesize

          @bytes.byteslice(@pos, length).tap { @pos += length }
        end

        # VICE 2.4.30 and later write their version after the machine name.
        def vice_version
          return unless @bytes.byteslice(@pos, VERSION_MAGIC.bytesize) == VERSION_MAGIC

          @pos += VERSION_MAGIC.bytesize
          take(8)
        end

        def section
          name = take(NAME_LENGTH).delete("\0")
          major, minor, length = take(6).unpack("CCV")
          raise FormatError, "module #{name} has a bad length #{length}" if length < MODULE_HEADER

          Section.new(name:, major:, minor:, data: take(length - MODULE_HEADER))
        end
      end
    end
  end
end
