# frozen_string_literal: true

module Badline
  module Media
    # Device 8 as a true 1541 instead of the KERNAL traps. Once a Drive1541
    # is plugged in as device 8, disk media go into it rather than into the
    # traps, so a LOAD runs the DOS and every byte crosses the serial bus.
    # A .g64 holds the disk's raw GCR, which only a true drive reads, so it
    # plugs one in when there's none yet. The 1541 reads only .d64 and .g64
    # images, so the traps' other disk media, a .d71, .d81 or .t64 or a host
    # directory, raise Error.
    module TrueDrive
      class Error < ArgumentError; end

      class << self
        # Plugs a Drive1541 in as device 8, unless one is there already, and
        # returns it.
        def plug(computer)
          drive(computer) || Drive1541.new.tap { |drive| computer.attach_drive1541(drive) }
        end

        # The Drive1541 on device 8, or nil.
        def drive(computer)
          drive = computer.drive1541
          drive if drive && drive.device == KernalTrap::Routine::DEVICE
        end

        # Whether the path goes in a true drive: a .g64 always, and other
        # disk media, which the traps would mount, when a true drive is
        # device 8.
        def takes?(computer, path)
          return true if File.extname(path).casecmp?(".g64")

          !drive(computer).nil? && (File.directory?(path) || MOUNT_TYPES.key?(File.extname(path).downcase))
        end

        # Puts the .d64 or .g64 in the drive on device 8, plugging one in
        # when there's none, and takes out what was mounted through the
        # traps, so LOAD and SAVE reach the drive too. `read_only` puts it
        # in write-protected.
        def insert(computer, path, read_only: false)
          unless %w[.d64 .g64].include?(File.extname(path).downcase)
            raise Error, "#{path} is not a .d64 or .g64 image, which the 1541 reads"
          end

          disk = Drive1541::Disk.open(path, read_only:)
          computer.unmount
          plug(computer).insert(disk)
          "Inserted #{path} in the 1541 as device 8"
        end
      end
    end
  end
end
