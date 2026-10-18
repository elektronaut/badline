# frozen_string_literal: true

module Badline
  module Media
    # Device 8 as a true drive instead of the KERNAL traps: a 1541, or on
    # the C128 its 1571, or on the Plus/4 a 1551 if it asks for one, or a
    # 1581, or on the PET a 2031 on the IEEE-488 bus. Once a true drive is plugged in as device 8, disk media go into
    # it rather than into the traps, so a LOAD runs the DOS and every byte
    # crosses the serial bus or TCBM. A .g64 holds the
    # disk's raw GCR, which only a true drive reads, so it plugs one in
    # when there's none yet. The 1541 reads only .d64 and .g64 images, the
    # 1571 .d71 and .g71 as well, and the 1581 only .d81, so a .d81 swaps
    # the drive on device 8 for a 1581 (Drives::Model1581::Slot), and another disk
    # image swaps a 1581 back for the machine's own drive. The PET has no
    # 1581, and its 2031 reads .d64 and .g64 images only. The traps' other
    # disk media, a .t64, a host directory, or a .d80 or .d82, raise Error.
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
          kind = Extensions.kind(path)
          return true if kind == :gcr

          !drive(computer).nil? && (File.directory?(path) || %i[disk archive ieee_disk].include?(kind))
        end

        # Puts the image in the drive on device 8, plugging one in that
        # reads it when the drive there doesn't, and takes out what was
        # mounted through the traps, so LOAD and SAVE reach the drive too.
        # `read_only` puts it in write-protected.
        def insert(computer, path, read_only: false)
          pet = computer.family == :pet
          return insert_d81(computer, path, read_only) if !pet && File.extname(path).casecmp?(".d81")

          drive = own_drive(computer)
          name = drive&.model_name || default_model(computer)
          types = name == "1571" ? %w[.d64 .g64 .d71 .g71] : %w[.d64 .g64]
          unless types.include?(File.extname(path).downcase)
            raise Error, "#{path} is not a #{types.join(' or ')} image, which the #{name} reads" if pet

            raise Error, "#{path} is not a #{types.join(', ')} or .d81 image, which the #{name} and the 1581 read"
          end

          drive ||= computer.plug_true_drive
          drive.insert_image(path, read_only:)
          computer.unmount
          "Inserted #{path} in the #{drive.model_name} as device 8"
        end

        private

        # The model plug_true_drive plugs in.
        def default_model(computer)
          case computer.family
          when :c128 then "1571"
          when :pet then "2031"
          else "1541"
          end
        end

        # The drive on device 8 unless it's a 1581.
        def own_drive(computer)
          drive = drive(computer)
          drive unless drive&.model_name == "1581"
        end

        def insert_d81(computer, path, read_only)
          drive = drive(computer)
          drive = computer.plug_drive1581 unless drive&.model_name == "1581"
          drive.insert_image(path, read_only:)
          computer.unmount
          "Inserted #{path} in the 1581 as device 8"
        end
      end
    end
  end
end
