# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      # The block availability map: a free count and a bitmap for each
      # track, with a set bit for each free sector. Each format says where
      # a track's count and bitmap sit, which tracks the map covers and
      # which of them hold the directory. Files are laid out as the DOS
      # does, on the tracks nearest the directory first, below it before
      # above, with the format's sector interleave within a track.
      module Bam
        # Whether the BAM has an entry for the block.
        def bam_block?(track, sector)
          bam_tracks.cover?(track) && sector.between?(0, sectors_in(track) - 1) &&
            block?(*bam_bitmap(track).first(2)) && block?(*bam_count(track).first(2))
        end

        # Whether the BAM marks the block free. A block it has no entry for
        # never is.
        def block_free?(track, sector)
          bam_block?(track, sector) && @bytes[bitmap_offset(track) + (sector / 8)][sector % 8] == 1
        end

        # The first free block past the one given, on its track and then
        # the tracks above it, for B-A to report when the block is taken.
        # Empty when there is none.
        def next_free_block(track, sector)
          bam_tracks.each do |candidate|
            next if candidate < track || reserved_tracks.include?(candidate)

            first = candidate == track ? sector + 1 : 0
            free = (first...sectors_in(candidate)).find { |s| block_free?(candidate, s) }
            return [candidate, free] if free
          end
          []
        end

        private

        def bitmap_offset(track)
          block_track, block_sector, offset = bam_bitmap(track)
          sector_offset(block_track, block_sector) + offset
        end

        def count_offset(track)
          block_track, block_sector, offset = bam_count(track)
          sector_offset(block_track, block_sector) + offset
        end

        # Marks the block free or in use, and moves the track's free count
        # with it. A block the BAM doesn't cover is left alone.
        def mark(track, sector, free)
          return if !bam_block?(track, sector) || block_free?(track, sector) == free

          byte = bitmap_offset(track) + (sector / 8)
          bit = 1 << (sector % 8)
          @bytes[byte] = free ? @bytes[byte] | bit : @bytes[byte] & ~bit
          @bytes[count_offset(track)] = (@bytes[count_offset(track)] + (free ? 1 : -1)) & 0xff
        end

        # Takes blocks for a chain, each placed after the one before it.
        # Raises DISK FULL when the disk runs out.
        def allocate_chain(count)
          block = nil
          Array.new(count) do
            block = next_block(*block) || raise(WriteError, WriteError::DISK_FULL)
            mark(*block, false)
            block
          end
        end

        # A chain's first block goes on the free track nearest the
        # directory. Each block after it goes the interleave further round
        # the same track, or on the next track out once that one is full.
        def next_block(track = nil, sector = nil)
          candidates = track ? [track, *tracks_after(track)] : allocation_order
          candidates.each do |candidate|
            free = free_sector(candidate, candidate == track ? sector + interleave : 0)
            return [candidate, free] if free
          end
          nil
        end

        def free_sector(track, first)
          count = sectors_in(track)
          (0...count).map { |i| (first + i) % count }.find { |s| block_free?(track, s) }
        end

        # The tracks a file can use, nearest the directory first, the one
        # below before the one above.
        def allocation_order
          (bam_tracks.to_a - reserved_tracks).sort_by do |track|
            [(track - directory_track).abs, track > directory_track ? 1 : 0]
          end
        end

        # The tracks further from the directory on the same side, then the
        # rest.
        def tracks_after(track)
          distance = (track - directory_track).abs
          below = track < directory_track
          further, rest = (allocation_order - [track]).partition do |candidate|
            (candidate < directory_track) == below && (candidate - directory_track).abs > distance
          end
          further + rest
        end
      end
    end
  end
end
