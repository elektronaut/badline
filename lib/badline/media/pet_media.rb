# frozen_string_literal: true

module Badline
  module Media
    # What a PET does with media of its own (Media.attach). Disks of every
    # kind, .d80 and .d82 among them, directories and .t64 archives mount
    # on device 8 through the traps on the KERNAL's IEEE-488 primitives
    # (PET::IEEETraps), and programs load at the start of BASIC, $0401
    # (Program). There is no cartridge port and no SID, and the true drives
    # are serial ones.
    module PETMedia
      # What a PET doesn't take.
      UNSUPPORTED = Extensions.of(%i[tune cartridge gcr tape])

      # What loads and runs the first program on the disk in device 8.
      AUTOSTART = %(load"*",8\rrun\r)

      class << self
        # BASIC 2 and 4 load the first program off the disk and run it.
        # BASIC 1's LOAD finds no device on the IEEE-488 bus, so the first
        # program goes in as a program file does, once the KERNAL has
        # booted.
        def disk_autostart(machine, storage)
          return machine.type_text(AUTOSTART) unless machine.model.basic1?

          data = storage.read_file("*")
          machine.on_init { Program.load(machine, data, autostart: true) } if data
        end
      end
    end
  end
end
