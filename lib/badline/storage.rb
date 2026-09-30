# frozen_string_literal: true

require "badline/storage/listing"
require "badline/storage/p00"
require "badline/storage/host_directory"
require "badline/storage/disk_image"
require "badline/storage/d64_image"
require "badline/storage/d71_image"
require "badline/storage/d81_image"
require "badline/storage/g64_image"
require "badline/storage/t64"
require "badline/storage/tap"
require "badline/storage/crt_file"
require "badline/storage/sid_file"
require "badline/storage/song_lengths"
require "badline/storage/unavailable"

module Badline
  module Storage
    FILE_TYPES = { "S" => :seq, "P" => :prg, "U" => :usr }.freeze

    # A write the disk refuses, with the DOS error it fails with.
    class WriteError < StandardError
      WRITE_PROTECT_ON = 26
      FILE_NOT_FOUND = 62
      FILE_EXISTS = 63
      DISK_FULL = 72

      attr_reader :code

      def initialize(code)
        @code = code
        super("DOS error #{code}")
      end
    end

    # The storage a snapshot's device 8 serves, by the number save_setup
    # writes first.
    HOST_DIRECTORY = 0
    D64 = 1
    D71 = 2
    D81 = 3
    T64_ARCHIVE = 4

    class << self
      # Opens the storage a save_setup wrote: the same directory or archive
      # by its path, or a disk image with the bytes it held, writes and
      # all. A detached reader gets the image write-protected, and
      # Unavailable for a directory or archive.
      def reopen(input)
        kind = input.int
        path = input.string
        case kind
        when HOST_DIRECTORY then input.detached? ? Unavailable.new : HostDirectory.new(path)
        when T64_ARCHIVE then input.detached? ? Unavailable.new : T64.new(path)
        else reopen_image(kind, path, input)
        end
      end

      # Folds shifted PETSCII letters to their ASCII equivalents.
      def ascii(bytes)
        bytes.map { |b| b.between?(0xc1, 0xda) ? b - 0x80 : b }.pack("C*")
      end

      # Decodes ISO-8859-1 bytes, the text of .sid headers and HVSC's
      # documents, to UTF-8.
      def latin1(bytes)
        bytes.pack("U*").force_encoding(Encoding::UTF_8)
      end

      # CBM DOS drive prefix: "0:NAME" selects a drive, "@0:NAME" is
      # save-with-replace
      def strip_drive_prefix(name)
        name.sub(/\A@?\d*:/, "")
      end

      # CBM DOS names read "NAME,TYPE,MODE". Returns the bare name and the
      # file type it asks for, or nil when it names none.
      def parse_name(name)
        base, type = strip_drive_prefix(name).split(",", 3)
        [base.to_s, FILE_TYPES[type.to_s.strip[0]&.upcase]]
      end

      def reopen_image(kind, path, input)
        read_only = input.boolean? || input.detached?
        bytes = input.blob
        case kind
        when D64 then D64Image.new(path, read_only:, bytes:)
        when D71 then D71Image.new(path, read_only:, bytes:)
        when D81 then D81Image.new(path, read_only:, bytes:)
        else raise Snapshot::FormatError, "unknown storage #{kind} in the state"
        end
      end

      # CBM-style filename pattern: "*" and "?" wildcards, case-insensitive.
      # The DOS stops comparing at the first "*", so whatever follows it
      # is ignored.
      def matcher(name)
        escaped = Regexp.escape(name.downcase.sub(/\*.*/m, "*"))
                        .gsub('\*', ".*")
                        .gsub('\?', ".")
        Regexp.new("\\A#{escaped}\\z")
      end
    end
  end
end
