# frozen_string_literal: true

module Badline
  module KernalTrap
    class DOS
      # Opens for writing, the S command and the reports a write makes. A
      # file open for writing takes the type its name asks for, or SEQ on a
      # data channel. On a write-protected disk, or storage that doesn't
      # write files through channels, an open for writing fails.
      module Writes
        private

        # A name already on the disk fails as FILE EXISTS unless @ asks to
        # replace it. A write-protected disk fails anything else and leaves
        # the channel closed.
        def open_write(secondary, name, file, type)
          replace = name.start_with?("@")
          if !replace && @storage.read_file(file, type: nil)
            @channels.close(secondary)
            return report(FILE_EXISTS)
          end
          return refuse_write(secondary) unless writable_disk?

          open_writer(secondary, WriteFile.new(file, type || :seq, mode: replace ? :replace : :write))
        end

        # An A mode open needs the file on the disk.
        def open_append(secondary, file, type)
          unless @storage.read_file(file, type:)
            @channels.close(secondary)
            return report(FILE_NOT_FOUND)
          end
          return refuse_append(secondary, file, type) unless writable_disk?

          open_writer(secondary, WriteFile.new(file, type, mode: :append))
        end

        def open_writer(secondary, channel)
          @channels.open_file(secondary, channel) ? report(OK) : report(NO_CHANNEL)
        end

        def writable_disk? = @storage.respond_to?(:writable?) && @storage.writable?

        # Runs a write to the disk and reports how it went. Returns whether
        # the disk took it.
        def writing
          written = yield != false
          @memory.read_bam if @memory.bam?
          written ? report(OK) : report(WRITE_PROTECT_ON)
          written
        rescue Storage::WriteError => e
          report(e.code)
          false
        end

        # An open for writing on a write-protected disk fails as WRITE
        # PROTECT ON.
        def refuse_write(secondary)
          @channels.close(secondary)
          report(WRITE_PROTECT_ON, *protected_block(secondary))
        end

        # An append on a write-protected disk fails at the file's last block,
        # the first one an append writes back.
        def refuse_append(secondary, file, type)
          @channels.close(secondary)
          report(WRITE_PROTECT_ON, *(@storage.last_block(file, type:) if @storage.respond_to?(:last_block)))
        end

        # SAVE's channel fails at the directory block its entry would go to,
        # a W mode open at the disk's header block.
        def protected_block(secondary)
          return [] unless @storage.respond_to?(:header_block)

          secondary == 1 ? @storage.new_entry_block : @storage.header_block
        end

        # S takes names separated by commas, each of which can be a pattern,
        # and reports how many files it scratched.
        def scratch(names)
          return report(WRITE_PROTECT_ON) unless writable_disk?

          count = 0
          scratched = writing do
            names.split(",").each { |name| count += @storage.scratch(Storage.strip_drive_prefix(name)) }
          end
          report(FILES_SCRATCHED, count) if scratched
        end
      end
    end
  end
end
