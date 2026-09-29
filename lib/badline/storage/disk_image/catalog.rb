# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      # The directory as LOAD"$" lists it: the disk name and ID from the
      # header block, every entry with a type, and the free blocks the BAM
      # counts outside the directory track.
      module Catalog
        HEADER_ID = 18
        ID_LENGTH = 5
        TYPE_MASK = 0x07

        def directory
          header = sector_at(*header_block)
          Listing.new(name: header[header_name, DiskImage::Directory::NAME_LENGTH],
                      id: header[header_name + HEADER_ID, ID_LENGTH],
                      entries: catalog_entries,
                      blocks_free:)
        end

        private

        # A slot whose type byte is zero is empty or scratched.
        def catalog_entries
          list = []
          each_sector(directory_track, directory_sector) do |data|
            (0...ENTRIES_PER_SECTOR).each do |i|
              entry = data[i * ENTRY_SIZE, ENTRY_SIZE]
              list << catalog_entry(entry) unless entry[2].zero?
            end
          end
          list
        end

        def catalog_entry(entry)
          Listing::Entry.new(name: entry[5, DiskImage::Directory::NAME_LENGTH],
                             type: entry[2] & TYPE_MASK,
                             blocks: entry[30] | (entry[31] << 8),
                             closed: entry[2].anybits?(DiskImage::Directory::CLOSED),
                             locked: entry[2].anybits?(0x40))
        end

        def blocks_free
          (bam_tracks.to_a - reserved_tracks).sum do |track|
            block?(*bam_count(track).first(2)) ? @bytes[count_offset(track)] : 0
          end
        end
      end
    end
  end
end
