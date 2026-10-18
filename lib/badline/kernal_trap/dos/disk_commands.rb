# frozen_string_literal: true

module Badline
  module KernalTrap
    class DOS
      # N, R and C: the commands that format a disk, rename a file and copy
      # files. Each takes its names after a colon. A name can't hold a
      # wildcard, and R and C take their new name before an "=". The DOS
      # here has one drive, so a file on drive 1 is never found, and C
      # without a colon, which copies a whole disk between the drives of a
      # dual drive, and D, which duplicates one, are invalid commands, as on
      # a single drive.
      module DiskCommands
        WILDCARD = /[*?]/
        OTHER_DRIVE = /\A[1-9]\d*:/
        DRIVE_ZERO = /\A0+:/

        private

        # N with an ID after a comma formats the disk, and without one only
        # clears it. The ID is the two bytes after the comma, which takes the
        # carriage return PRINT# ends the command with when the ID is one
        # character. A comma with nothing after it gives no ID.
        def new_disk(text)
          colon = text.index(":")
          return report(NO_FILE_GIVEN) unless colon

          command = text.chomp("\r")
          name, id = command[(colon + 1)..].split(",", 2)
          return report(SYNTAX_ERROR) if name.to_s.match?(/[*?=]/)
          return report(WRITE_PROTECT_ON) unless @storage.respond_to?(:format)

          id = id.to_s.empty? ? nil : text.bytes[(command.index(",") + 1), 2]
          writing { @storage.format(name.to_s, id && (id + [Storage::DiskImage::NAME_PADDING]).first(2)) }
        end

        # R takes the new name, then the file's.
        def rename_file(text)
          new_name, old_names = file_names(text, NO_FILE_GIVEN)
          return unless new_name
          return report(SYNTAX_ERROR) unless old_names.one?
          return report(WRITE_PROTECT_ON) unless @storage.respond_to?(:rename)
          return report(FILE_NOT_FOUND) if old_names.first.match?(OTHER_DRIVE)

          writing { @storage.rename(Storage.strip_drive_prefix(old_names.first), new_name) }
        end

        # C takes the new name, then the files it joins, separated by
        # commas. A first file named with drive 0 that is the new file
        # itself has the others added to its end.
        def copy_file(text)
          new_name, old_names = file_names(text, INVALID_COMMAND)
          return unless new_name
          return report(WRITE_PROTECT_ON) unless @storage.respond_to?(:copy)
          return report(FILE_NOT_FOUND) if old_names.any? { |name| name.match?(OTHER_DRIVE) }

          names = old_names.map { |name| Storage.strip_drive_prefix(name) }
          in_place = old_names.first.match?(DRIVE_ZERO) && names.first == new_name
          writing { in_place ? @storage.concat(new_name, names.drop(1)) : @storage.copy(new_name, names) }
        end

        # The new name and the old ones of "new=old,...", or nil once it
        # has reported what's wrong.
        def file_names(text, missing_colon)
          colon = text.index(":")
          return report(missing_colon) unless colon

          new_name, rest = text[(colon + 1)..].split("=", 2)
          new_name = new_name.to_s
          return report(SYNTAX_ERROR) if rest.nil? || new_name.include?(",")

          old_names = rest.empty? ? [""] : rest.split(",", -1)
          return report(SYNTAX_ERROR) if [new_name, *old_names].any? { |name| name.match?(WILDCARD) }

          [new_name, old_names]
        end
      end
    end
  end
end
