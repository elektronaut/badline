# frozen_string_literal: true

require "badline/drive1581/disk_state"

module Badline
  class Drive1581
    # A 3.5" double-sided disk as the WD1772 sees it: a Track on each side
    # of 80 cylinders, or none where it was never formatted.
    #
    # A .d81 image holds the 1581 DOS's logical blocks in order, 40 of 256
    # bytes on each logical track 1 to 80 (1581 Service Manual, format
    # organization). Logical track t is cylinder t - 1, and the DOS puts
    # its sectors 0 to 19 on side 0 and 20 to 39 on side 1, two to each
    # 512-byte physical sector, numbered from 1. So physical sector s on
    # side h of cylinder c holds logical sectors 20h + 2(s - 1) and the one
    # after it, and every cylinder of the image is a standard Track
    # (Track.standard) on both sides. A block the image's error table
    # marks 20 or 21 loses its sector's ID field, 27 spoils the ID's CRC,
    # 22 loses the data field and 23 spoils its CRC.
    #
    # The WD1772 writes into the tracks, and flush stores the standard
    # sectors of each one written back in the image, which writes its host
    # file. A track formatted another way stays on the disk alone. The disk
    # is write-protected when the image won't take writes.
    class Disk
      include State

      CYLINDERS = 80
      SIDES = 2

      # Logical blocks a side of a cylinder holds.
      SIDE_BLOCKS = 20

      # A logical block's bytes, and how many a physical sector holds.
      BLOCK_SIZE = 256
      BLOCKS = Track::SECTOR_SIZE / BLOCK_SIZE

      # A disk from the .d81 image at +path+. `read_only` opens the image
      # write-protected.
      def self.open(path, read_only: false)
        new(Storage::D81Image.new(path, read_only:)).opened(path, read_only)
      end

      attr_reader :image

      def initialize(image = nil)
        @image = image
        @tracks = Array.new(CYLINDERS * SIDES)
        @written = {}
        @changed = {}
        @path = nil
        @read_only = false
      end

      # The Track on +side+ of +cylinder+, or nil where there is none: past
      # the image's cylinders, or on a disk without an image that the head
      # never formatted.
      def track(cylinder, side)
        index = (cylinder * SIDES) + side
        return @tracks[index] if @tracks[index] || !@image || cylinder >= CYLINDERS

        @tracks[index] = image_track(cylinder, side)
      end

      # A write track laid +track+ down on +side+ of +cylinder+, or a write
      # sector changed it.
      def write(cylinder, side, track)
        return if cylinder >= CYLINDERS

        index = (cylinder * SIDES) + side
        @tracks[index] = track
        @written[index] = true
        @changed[index] = true
      end

      # Whether the write-protect hole is open: the disk's image won't take
      # writes, or a disk without an image was opened read-only.
      def write_protected? = @image.nil? ? @read_only : !@image.writable?

      # Whether any track was written since the last flush.
      def written? = !@written.empty?

      # Stores the standard sectors of each track written since the last
      # flush in the image, all in one write to its host file.
      def flush
        written = @written.keys.sort
        @written.clear
        return if @image.nil? || written.empty?

        @image.store_blocks(written.flat_map { |index| track_blocks(index / SIDES, index % SIDES) })
      end

      private

      def image_track(cylinder, side)
        track = Track.standard(cylinder, side) { |sector| physical_block(cylinder, side, sector) }
        track.sectors.each { |sector| mark_errors(cylinder, side, sector) }
        track.sectors.reject! { |sector| sector.id.nil? }
        track
      end

      # The logical track and first sector physical sector +sector+ holds.
      def logical(cylinder, side, sector) = [cylinder + 1, (side * SIDE_BLOCKS) + ((sector - 1) * BLOCKS)]

      def physical_block(cylinder, side, sector)
        track, first = logical(cylinder, side, sector)
        Array.new(BLOCKS) { |i| @image.read_block(track, first + i) || [] }.flatten
      end

      def mark_errors(cylinder, side, sector)
        track, first = logical(cylinder, side, sector.id.bytes[2])
        errors = Array.new(BLOCKS) { |i| @image.block_error(track, first + i) }
        sector.id.good = false if errors.include?(27)
        sector.data.good = false if errors.include?(23)
        sector.data = nil if errors.include?(22)
        sector.id = nil if errors.include?(20) || errors.include?(21)
      end

      # [track, sector, data, nil] for DiskImage#store_blocks, for each
      # logical block a standard sector of the track holds.
      def track_blocks(cylinder, side)
        track = @tracks[(cylinder * SIDES) + side]
        Track::SECTORS.times.flat_map do |index|
          data = track.sector([cylinder, side, index + 1, Track::SIZE_CODE])&.data
          next [] unless data

          logical_track, first = logical(cylinder, side, index + 1)
          Array.new(BLOCKS) do |i|
            [logical_track, first + i, data.bytes[i * BLOCK_SIZE, BLOCK_SIZE], nil]
          end
        end
      end
    end
  end
end
