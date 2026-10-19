# frozen_string_literal: true

module Badline
  module Storage
    # A D9060 or D9090 hard disk: 153 cylinders of 32 blocks a head, four
    # heads on the D9060 and six on the D9090. DOS 3.0 numbers a block by
    # its cylinder as the track, from 0, and by head × 32 + sector as the
    # sector. The controller numbers the same block by its place in the
    # image (LBA), and reads and writes it there.
    #
    # The image's size tells the two apart. One of another size, such as an
    # empty file to format, takes the heads it's given, or four, and reads as
    # zeros past its end.
    class D90Image < DiskImage
      CYLINDERS = 153
      SECTORS_PER_HEAD = 32

      # The heads of each drive, by the size of its image.
      HEADS = { 5_013_504 => 4, 7_520_256 => 6 }.freeze

      # The BAM entry of a head: a free count and a four-byte bitmap.
      ENTRY = 5

      # The heads of the drive an image of the size belongs to, or nil for
      # a size neither has.
      def self.heads_for(size) = HEADS[size]

      attr_reader :heads

      def initialize(path, read_only: false, bytes: nil, heads: nil)
        super(path, read_only:, bytes:)
        @heads = heads || HEADS.fetch(@bytes.length, 4)
        @bytes.fill(0, @bytes.length...(block_count * SECTOR_SIZE))
      end

      def sectors_in(_track) = @heads * SECTORS_PER_HEAD

      # The blocks the disk holds.
      def block_count = CYLINDERS * sectors_in(0)

      # The controller's number for the block.
      def lba(track, sector) = (track * sectors_in(track)) + sector

      def header_block = [76, 20]

      # Whether the disk holds the blocks from the LBA on.
      def blocks?(lba, count) = lba >= 0 && lba + count <= block_count

      # The bytes of the blocks from the LBA on, or nil when the disk
      # doesn't hold them all.
      def read_blocks(lba, count)
        @bytes[lba * SECTOR_SIZE, count * SECTOR_SIZE] if blocks?(lba, count)
      end

      # Writes whole blocks from the LBA on, straight to the host file. It
      # writes nothing when the disk doesn't hold them all. A disk that
      # takes no writes raises WRITE PROTECT ON and keeps its blocks.
      def write_blocks(lba, bytes)
        return unless (bytes.length % SECTOR_SIZE).zero? && blocks?(lba, bytes.length / SECTOR_SIZE)
        raise WriteError, WriteError::WRITE_PROTECT_ON unless writable?

        store(lba * SECTOR_SIZE, bytes)
        @bytes[lba * SECTOR_SIZE, bytes.length] = bytes
        @entries = nil
      end

      def bam_block?(track, sector) = block?(track, sector)

      def block_free?(track, sector)
        block?(track, sector) && @bytes[bitmap_byte(track, sector)][sector % 8] == 1
      end

      private

      def error_tables = {}

      def store(offset, bytes)
        File.open(@path, "r+b") do |file|
          file.seek(offset)
          file.write(bytes.pack("C*"))
        end
      rescue SystemCallError
        raise WriteError, WriteError::WRITE_PROTECT_ON
      end

      def block?(track, sector)
        track.between?(0, CYLINDERS - 1) && sector.between?(0, sectors_in(track) - 1)
      end

      def track_offset(track) = track * sectors_in(track)

      def clear_blocks
        header = sector_offset(*header_block)
        @bytes.fill(0, 0, header)
        @bytes.fill(0, header + SECTOR_SIZE, (block_count * SECTOR_SIZE) - header - SECTOR_SIZE)
      end

      # The header at 76/20 holds the disk name at $06 and the ID at $18,
      # after the link to the directory's first block, 76/10.
      def header_name = 0x06
      def directory_track = 76
      def directory_sector = 10
      def directory_interleave = 3
      def interleave = 10
      def reserved_tracks = [76]

      # A link to track 0 ends a chain, so files never go there.
      def allocation_order = super - [0]

      def bam_tracks = 0..(CYLINDERS - 1)
      def header_link = [76, 10]
      def dos_type = "3A"
      def header_tail = 4

      # The header holds no format letter after its link.
      def write_header(name, id)
        super
        write_at(*header_block, 2, [0])
      end

      # The BAM takes sector 0 of a cylinder for each group of cylinders
      # its entries fit in, twelve on a D9060 and eight on a D9090: the
      # cylinder after the group's first, or the last one for a group of
      # one at the end.
      def tracks_per_bam_block = (SECTOR_SIZE - 16) / (@heads * ENTRY)

      def bam_block_track(track)
        first = track - (track % tracks_per_bam_block)
        [first + 1, CYLINDERS - 1].min
      end

      def entry_offset(track, sector)
        group = track % tracks_per_bam_block
        sector_offset(bam_block_track(track), 0) + 16 +
          (((group * @heads) + (sector / SECTORS_PER_HEAD)) * ENTRY)
      end

      def bitmap_byte(track, sector) = entry_offset(track, sector) + 1 + ((sector % SECTORS_PER_HEAD) / 8)

      def mark(track, sector, free)
        return if !block?(track, sector) || block_free?(track, sector) == free

        entry = entry_offset(track, sector)
        byte = bitmap_byte(track, sector)
        bit = 1 << (sector % 8)
        @bytes[byte] = free ? @bytes[byte] | bit : @bytes[byte] & ~bit
        @bytes[entry] = (@bytes[entry] + (free ? 1 : -1)) & 0xff
      end

      def free_track(track)
        @heads.times do |head|
          @bytes[entry_offset(track, head * SECTORS_PER_HEAD), ENTRY] = [SECTORS_PER_HEAD, 0xff, 0xff, 0xff, 0xff]
        end
      end

      def blocks_free
        (bam_tracks.to_a - reserved_tracks).sum do |track|
          (0...@heads).sum { |head| @bytes[entry_offset(track, head * SECTORS_PER_HEAD)] }
        end
      end

      # Block 0/0 points at the bad-block list in 0/1, the directory, the
      # header and the BAM's first block, and holds the ID. Each BAM block
      # links the next and the one before it, $FF $FF at either end, and
      # names the first cylinder it covers and the one past its last.
      def bam_headers(id)
        groups = bam_tracks.each_slice(tracks_per_bam_block).to_a
        blocks = groups.map { |tracks| bam_block_track(tracks.first) }
        bam = groups.each_with_index.map do |tracks, i|
          following = i == groups.length - 1 ? [0xff, 0xff] : [blocks[i + 1], 0]
          previous = i.zero? ? [0xff, 0xff] : [blocks[i - 1], 0]
          [blocks[i], 0, [*following, *previous, tracks.first, tracks.last + 1]]
        end
        [[0, 0, [0, 1, 0, 0xff, *header_link, *header_block, blocks.first, 0, *id]],
         [0, 1, Array.new(SECTOR_SIZE, 0xff)], *bam]
      end
    end
  end
end
