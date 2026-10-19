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

        # The model of the true drive on device 8, or an empty one for the
        # traps.
        def drive_model(computer)
          drive = Media::TrueDrive.drive(computer)
          drive.nil? ? "" : drive.model_name
        end

        def eject_disk(computer)
          drive = Media::TrueDrive.drive(computer)
          drive.nil? ? computer.unmount : drive.insert(nil)
        end

        # Whether the expansion port has a cartridge in, on the Plus/4 in
        # either cartridge's slots.
        def cartridge?(computer)
          return !computer.cartridge_slots.empty? if computer.family == :plus4
          return false if %i[pet cbm2 kim1].include?(computer.family)

          !computer.address_bus.cartridge.nil?
        end

        # Takes the cartridge out with the power off, on the Plus/4 both.
        def remove_cartridge(computer)
          return computer.detach_cartridges if computer.family == :plus4

          computer.address_bus.detach_cartridge
          computer.power_cycle!
        end
      end
    end
  end
end
