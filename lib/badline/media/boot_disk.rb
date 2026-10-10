# frozen_string_literal: true

module Badline
  module Media
    # A C128 boot disk. At power-on the C128 KERNAL reads track 1, sector 0
    # of the disk in device 8 and runs it when it starts with "CBM", as boot
    # games have it. The 1581's DOS first loads and runs a USR file named
    # COPYRIGHT CBM 86 when the disk has one, which is how CP/M's 1581 disks
    # hand the KERNAL their boot sector, so a .d81 with that file boots too.
    #
    # On a C128 in C128 mode a boot disk goes in a true drive, a 1581 for a
    # .d81 and the C128D's 1571 otherwise, and nothing is typed, so the
    # KERNAL boots it. Other disks, and other machines, keep the traps and
    # the autostart.
    module BootDisk
      SIGNATURE = "CBM".bytes.freeze
      AUTO_BOOT = "copyright cbm 86"
      TYPES = %w[.d64 .d71 .d81].freeze

      class << self
        def takes?(computer, path)
          computer.family == :c128 && computer.mode == :c128 && boot?(path)
        end

        # Puts a disk that boots on the computer in a true drive as device
        # 8, write-protected with `disk: { read_only: true }`, for the KERNAL
        # to boot at power-on, and says so. Nil for any other disk.
        def attach(computer, path, disk: {}, **)
          return unless takes?(computer, path)

          read_only = disk.fetch(:read_only, false)
          "#{TrueDrive.insert(computer, path, read_only:)}, to boot at power-on"
        end

        # Whether the disk image at path boots: its boot sector, or on a
        # .d81 the 1581's auto-boot file.
        def boot?(path)
          type = File.extname(path).downcase
          return false unless TYPES.include?(type) && File.file?(path)

          image = Media.open_storage(path, { read_only: true })
          block = image.read_block(1, 0)
          return true if block && block[0, 3] == SIGNATURE

          type == ".d81" && !image.read_file(AUTO_BOOT, type: :usr).nil?
        end
      end
    end
  end
end
