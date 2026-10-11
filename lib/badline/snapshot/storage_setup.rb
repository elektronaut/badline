# frozen_string_literal: true

module Badline
  module Snapshot
    # The storage device 8 serves through the traps, as a State holds it:
    # its kind, its path and, for an archive or a disk image, its bytes, so
    # it opens again without the host file.
    module StorageSetup
      HOST_DIRECTORY = 0
      D64 = 1
      D71 = 2
      D81 = 3
      T64_ARCHIVE = 4

      module_function

      # The same directory by its path, an archive with the bytes it held,
      # or a disk image with its path, whether it is write-protected, and
      # its bytes with the error table after them.
      def write(storage, out)
        if storage.is_a?(Storage::HostDirectory)
          out.int(HOST_DIRECTORY).string(File.expand_path(storage.path))
        elsif storage.is_a?(Storage::T64)
          out.int(T64_ARCHIVE).string(File.expand_path(storage.path)).blob(storage.bytes)
        else
          write_image(storage, out)
        end
      end

      def write_image(image, out)
        out.int(image_kind(image)).string(File.expand_path(image.path)).boolean(image.read_only?).blob(image.contents)
      end

      def image_kind(image)
        return D71 if image.is_a?(Storage::D71Image)
        return D64 if image.is_a?(Storage::D64Image)
        return D81 if image.is_a?(Storage::D81Image)

        raise ArgumentError, "#{image.class} can't go in a snapshot"
      end

      # The storage's kind by name, in a keyed snapshot module, under
      # storage.*: its path, and for an archive or a disk image whether it
      # is write-protected and its bytes.
      def write_fields(storage, out)
        out.text("storage.path", File.expand_path(storage.path))
        if storage.is_a?(Storage::HostDirectory)
          out.text("storage.kind", "directory")
        elsif storage.is_a?(Storage::T64)
          out.text("storage.kind", "t64").bytes("storage.bytes", storage.bytes)
        else
          out.text("storage.kind", KIND_NAMES.fetch(image_kind(storage))).bool("storage.read_only", storage.read_only?)
          out.bytes("storage.bytes", storage.contents)
        end
      end

      KIND_NAMES = %w[directory d64 d71 d81 t64].freeze

      # Opens the storage write_fields wrote, as read opens the one write
      # wrote.
      def read_fields(input, detached: false)
        kind = KIND_NAMES.index(input.choice("storage.kind", KIND_NAMES, "directory")).to_i
        path = input.text("storage.path", "")
        return (detached ? Storage::Unavailable.new : Storage::HostDirectory.new(path)) if kind == HOST_DIRECTORY

        bytes = input.bytes("storage.bytes", "".b).bytes
        return Storage::T64.new(path, bytes:) if kind == T64_ARCHIVE

        read_only = input.bool("storage.read_only", false) || detached
        case kind
        when D64 then Storage::D64Image.new(path, read_only:, bytes:)
        when D71 then Storage::D71Image.new(path, read_only:, bytes:)
        else Storage::D81Image.new(path, read_only:, bytes:)
        end
      end

      # Opens the storage `write` wrote: the same directory by its path, an
      # archive with the bytes it held, or a disk image with the bytes it
      # held, writes and all. A detached reader gets the image
      # write-protected, and Storage::Unavailable for a directory.
      def read(input)
        kind = input.int
        path = input.string
        case kind
        when HOST_DIRECTORY then input.detached? ? Storage::Unavailable.new : Storage::HostDirectory.new(path)
        when T64_ARCHIVE then Storage::T64.new(path, bytes: input.blob)
        else read_image(kind, path, input)
        end
      end

      def read_image(kind, path, input)
        read_only = input.boolean? || input.detached?
        bytes = input.blob
        case kind
        when D64 then Storage::D64Image.new(path, read_only:, bytes:)
        when D71 then Storage::D71Image.new(path, read_only:, bytes:)
        when D81 then Storage::D81Image.new(path, read_only:, bytes:)
        else raise FormatError, "unknown storage #{kind} in the state"
        end
      end
    end
  end
end
