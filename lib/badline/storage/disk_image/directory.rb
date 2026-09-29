# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      # Directory entries as writes make them: a closed file's type, its
      # first block and its length in blocks, under a name padded with
      # shifted spaces. The directory grows a block at a time on its track.
      module Directory
        CLOSED = 0x80
        NAME_LENGTH = 16

        private

        def entry_named(name)
          wanted = decode_name(encode_name(name))
          entries.find { |entry| entry[:name] == wanted }
        end

        def encode_name(name)
          bytes = name.upcase.bytes.first(NAME_LENGTH)
          bytes + Array.new(NAME_LENGTH - bytes.length, NAME_PADDING)
        end

        # The new chain is written before the old one is freed, so a
        # replace that runs out of room leaves the old file.
        def rewrite(entry, bytes, type)
          blocks = write_chain(bytes)
          free_chain(entry)
          write_entry(entry[:offset], type, blocks)
        end

        def add_file(name, bytes, type)
          blocks = write_chain(bytes)
          offset = free_entry_offset
          @bytes[offset + 5, NAME_LENGTH] = encode_name(name)
          write_entry(offset, type, blocks)
        end

        # The slot's first two bytes link the directory block, so they
        # stay. The name stays too, and what follows it up to the block
        # count is cleared.
        def write_entry(offset, type, blocks)
          @bytes[offset + 2] = CLOSED | FILETYPES.fetch(type)
          @bytes[offset + 3, 2] = blocks.first
          @bytes[offset + 21, 9] = Array.new(9, 0)
          @bytes[offset + 30, 2] = [blocks.length & 0xff, blocks.length >> 8]
        end

        # The first free slot in the directory, which grows by a block on
        # the directory track when every slot is taken.
        def free_entry_offset
          last = nil
          each_sector(directory_track, directory_sector) do |data, track, sector|
            slot = (0...ENTRIES_PER_SECTOR).find { |i| data[(i * ENTRY_SIZE) + 2].zero? }
            return sector_offset(track, sector) + (slot * ENTRY_SIZE) if slot

            last = [track, sector]
          end
          sector_offset(*extend_directory(*last))
        end

        # A new directory block goes the directory interleave on from the
        # last one. A full directory track fails as DISK FULL.
        def extend_directory(track, sector)
          count = sectors_in(directory_track)
          free = (0...count).map { |i| (sector + directory_interleave + i) % count }
                            .find { |s| block_free?(directory_track, s) }
          raise WriteError, WriteError::DISK_FULL unless free

          mark(directory_track, free, false)
          @bytes[sector_offset(track, sector), 2] = [directory_track, free]
          put_sector(directory_track, free, [0, 0xff])
          [directory_track, free]
        end
      end
    end
  end
end
