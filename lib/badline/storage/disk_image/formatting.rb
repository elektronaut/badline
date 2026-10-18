# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      # The DOS's N command. With an ID it formats the disk: every block of
      # the tracks the BAM covers is cleared, and the header, the BAM and an
      # empty directory are written. Without one it only clears the disk:
      # the header takes the new name and keeps its ID and whatever else it
      # held, the BAM marks every block free, and the directory's first
      # block is emptied. Either way the header, the BAM's blocks and the
      # first directory block stay in use. Each format says where these go.
      module Formatting
        # The disk's ID, as the header holds it.
        def disk_id = sector_at(*header_block)[header_name + Catalog::HEADER_ID, 2]

        # Formats the disk under the name, or with no ID clears it.
        def format(name, id = nil)
          update_image do
            full = !id.nil?
            put_sector(*header_block, []) if full
            id = (id || disk_id).first(2)
            write_header(name, id)
            clear_blocks if full
            headers = bam_headers(id)
            headers.each { |track, sector, bytes| write_at(track, sector, 0, bytes) }
            put_sector(directory_track, directory_sector, [0, 0xff])
            bam_tracks.each { |track| free_track(track) }
            [header_block, *headers.map { |track, sector, _| [track, sector] }, [directory_track, directory_sector]]
              .each { |block| mark(*block, false) }
          end
        end

        private

        # Every block the BAM covers but the header.
        def clear_blocks
          bam_tracks.each do |track|
            (0...sectors_in(track)).each do |sector|
              put_sector(track, sector, []) unless [track, sector] == header_block
            end
          end
        end

        # The link to the next block, the format's letter, the name, the ID
        # and the DOS type, each field after the name set off with shifted
        # spaces.
        def write_header(name, id)
          write_at(*header_block, 0, [*header_link, dos_type.getbyte(1), 0])
          write_at(*header_block, header_name,
                   encode_name(name) + [NAME_PADDING, NAME_PADDING] + id + [NAME_PADDING] +
                   dos_type.bytes + Array.new(header_tail, NAME_PADDING))
        end

        # A free track counts its sectors and sets a bit for each.
        def free_track(track)
          count = sectors_in(track)
          bits = (1 << count) - 1
          @bytes[count_offset(track)] = count
          bitmap_size.times { |i| @bytes[bitmap_offset(track) + i] = (bits >> (8 * i)) & 0xff }
        end

        def write_at(track, sector, offset, bytes)
          @bytes[sector_offset(track, sector) + offset, bytes.length] = bytes
        end
      end
    end
  end
end
