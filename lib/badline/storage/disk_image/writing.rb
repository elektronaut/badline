# frozen_string_literal: true

module Badline
  module Storage
    class DiskImage
      # Writes to the image: files with their chains, directory entries and
      # BAM, raw blocks, and BAM changes. Each write goes back to the host
      # file at once. A write the disk refuses raises WriteError and leaves
      # the image as it was, and so does one the host can't store, which
      # fails as a write-protected disk does.
      module Writing
        # Whether the host file takes writes.
        def writable? = ::File.writable?(@path)

        # Writes a new file, or with `replace` writes over the one of the
        # same name in its directory entry. A name already on the disk
        # fails as FILE EXISTS otherwise.
        def write_file(name, bytes, type: :prg, replace: false)
          existing = entry_named(name)
          raise WriteError, WriteError::FILE_EXISTS if existing && !replace

          update_image do
            existing ? rewrite(existing, bytes, type) : add_file(name, bytes, type)
          end
        end

        # Adds the bytes to the end of a file, which keeps its type and its
        # directory entry.
        def append_file(name, bytes, type: nil)
          entry = find_entry(name, type)
          raise WriteError, WriteError::FILE_NOT_FOUND unless entry

          update_image { rewrite(entry, read_chain(entry[:track], entry[:sector]) + bytes, entry[:type]) }
        end

        # Scratches the files matching the pattern, of any type, except
        # locked ones, and frees their blocks. Returns how many it
        # scratched.
        def scratch(name)
          pattern = Storage.matcher(name)
          files = entries.select { |entry| !entry[:locked] && pattern.match?(entry[:name]) }
          return 0 if files.empty?

          update_image do
            files.each do |entry|
              free_chain(entry)
              @bytes[entry[:offset] + 2] = 0
            end
          end
          files.length
        end

        # Raw block access for the DOS `U2` command. A block that the error
        # table marks bad reads cleanly once written.
        def write_block(track, sector, data)
          update_image { put_sector(track, sector, data) } if block?(track, sector)
        end

        # Marks a block in use, as B-A does.
        def allocate_block(track, sector) = update_image { mark(track, sector, false) }

        # Marks a block free, as B-F does.
        def free_block(track, sector) = update_image { mark(track, sector, true) }

        private

        def update_image
          raise WriteError, WriteError::WRITE_PROTECT_ON unless writable?

          saved = [@bytes.dup, @errors&.dup]
          begin
            yield
            ::File.binwrite(@path, (@bytes + @errors.to_a).pack("C*"))
          rescue WriteError, SystemCallError => e
            @bytes, @errors = saved
            raise e.is_a?(WriteError) ? e : WriteError.new(WriteError::WRITE_PROTECT_ON)
          ensure
            @entries = nil
          end
        end

        # Every block links the next, and the last one holds the index of
        # its last byte in place of a link. An empty file still takes one.
        def write_chain(bytes)
          chunks = bytes.each_slice(SECTOR_SIZE - 2).to_a
          chunks = [[]] if chunks.empty?
          blocks = allocate_chain(chunks.length)
          blocks.each_with_index do |block, i|
            link = blocks[i + 1] || [0, chunks[i].length + 1]
            put_sector(*block, link + chunks[i])
          end
          blocks
        end

        def free_chain(entry)
          each_sector(entry[:track], entry[:sector]) do |_data, track, sector|
            mark(track, sector, true)
          end
        end

        def put_sector(track, sector, data)
          block = data.first(SECTOR_SIZE)
          @bytes[sector_offset(track, sector), SECTOR_SIZE] = block + Array.new(SECTOR_SIZE - block.length, 0)
          @errors[track_offset(track) + sector] = 1 if @errors
        end
      end
    end
  end
end
