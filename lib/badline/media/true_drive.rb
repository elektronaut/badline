# frozen_string_literal: true

module Badline
  module Media
    # Device 8 as a true drive instead of the KERNAL traps: a 1541, or on
    # the C128 its 1571. Once a true drive is plugged in as device 8, disk
    # media go into it rather than into the traps, so a LOAD runs the DOS
    # and every byte crosses the serial bus. A .g64 holds the disk's raw
    # GCR, which only a true drive reads, so it plugs one in when there's
    # none yet. The 1541 reads only .d64 and .g64 images, and the 1571
    # .d71 and .g71 as well, so the traps' other disk media, a .d81 or
    # .t64 or a host directory, raise Error.
    module TrueDrive
      class Error < ArgumentError; end

      class << self
        # Plugs the machine's true drive in as device 8, unless one is there
        # already, and returns it.
        def plug(computer)
          drive(computer) || computer.plug_true_drive
        end

        # The true drive on device 8, or nil.
        def drive(computer)
          drive = computer.true_drive
          drive if drive && drive.device == KernalTrap::Routine::DEVICE
        end

        # Whether the path goes in a true drive: a .g64 or .g71 always, and
        # other disk media, which the traps would mount, when a true drive
        # is device 8.
        def takes?(computer, path)
          return true if %w[.g64 .g71].include?(File.extname(path).downcase)

          !drive(computer).nil? && (File.directory?(path) || MOUNT_TYPES.key?(File.extname(path).downcase))
        end

        # Puts the image in the drive on device 8, plugging one in when
        # there's none, and takes out what was mounted through the traps,
        # so LOAD and SAVE reach the drive too. `read_only` puts it in
        # write-protected.
        def insert(computer, path, read_only: false)
          name = drive(computer)&.model_name || (computer.family == :c128 ? "1571" : "1541")
          types = name == "1571" ? %w[.d64 .g64 .d71 .g71] : %w[.d64 .g64]
          unless types.include?(File.extname(path).downcase)
            raise Error, "#{path} is not a #{types[0..-2].join(', ')} or #{types.last} image, which the #{name} reads"
          end

          disk = Drive1541::Disk.open(path, read_only:)
          computer.unmount
          plug(computer).insert(disk)
          "Inserted #{path} in the #{name} as device 8"
        end
      end
    end
  end
end
