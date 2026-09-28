# frozen_string_literal: true

module Badline
  module Media
    # Device 8 as a true 1541 instead of the KERNAL traps. Once a Drive1541
    # is plugged in as device 8, disk media go into it rather than into the
    # traps, so a LOAD runs the DOS and every byte crosses the serial bus.
    # The 1541 reads only .d64 images, so the traps' other disk media, a
    # .d71, .d81 or .t64 or a host directory, raise Error.
    module TrueDrive
      class Error < StandardError; end

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

        # Whether the path is disk media, which the traps would mount, and
        # a true drive is there to take it instead.
        def takes?(computer, path)
          !drive(computer).nil? && (File.directory?(path) || MOUNT_TYPES.key?(File.extname(path).downcase))
        end

        # Puts the .d64 in the drive.
        def insert(computer, path)
          raise Error, "the true drive reads only .d64 disk images" unless File.extname(path).downcase == ".d64"

          drive(computer).insert(Drive1541::Disk.from_d64(Storage::D64Image.new(path)))
          "Inserted #{path} in the true drive"
        end
      end
    end
  end
end
