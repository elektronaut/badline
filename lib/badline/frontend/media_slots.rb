# frozen_string_literal: true

module Badline
  module Frontend
    # The machine's media slots as the pause menu and the --at events
    # both take media out of them: device 8, a true drive there or else
    # the KERNAL traps, and the expansion port.
    module MediaSlots
      class << self
        # Whether device 8 has a disk in.
        def disk?(computer)
          drive = Media::TrueDrive.drive(computer)
          drive.nil? ? computer.mounted? : !drive.disk.nil?
        end

        # The expanded path of the disk in device 8, however it went in, or
        # an empty one.
        def disk_path(computer)
          drive = Media::TrueDrive.drive(computer)
          unless drive.nil?
            disk = drive.disk
            return disk.nil? ? "" : disk.path.to_s
          end

          path = computer.mounted_path
          path.empty? ? path : File.expand_path(path)
        end

        def eject_disk(computer)
          drive = Media::TrueDrive.drive(computer)
          drive.nil? ? computer.unmount : drive.insert(nil)
        end

        # Takes the cartridge out with the power off.
        def remove_cartridge(computer)
          computer.address_bus.detach_cartridge
          computer.power_cycle!
        end
      end
    end
  end
end
