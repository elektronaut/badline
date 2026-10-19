# frozen_string_literal: true

module Badline
  module Media
    # What a PET does with media of its own (Media.attach). Disks of every
    # kind, .d80 and .d82 among them, directories and .t64 archives mount
    # on device 8 through the traps on the KERNAL's IEEE-488 primitives
    # (PET::IEEETraps), programs load at the start of BASIC, $0401
    # (Program), and tapes play on the datasette at cassette port #1. There
    # is no cartridge port and no SID, and the true drives are serial ones.
    module PETMedia
      # What a PET doesn't take.
      UNSUPPORTED = Extensions.of(%i[tune cartridge])

      # What loads and runs the first program on the disk in device 8.
      AUTOSTART = %(load"*",8\rrun\r)

      # What loads and runs the first program on the tape in cassette #1.
      TAPE_AUTOSTART = "load\rrun\r"

      class << self
        # A tape made for another machine plays all the same, and says so.
        def tape_message(tape, message)
          tape.platform == Storage::TAP::PET_PLATFORM ? message : "#{message}, a tape for another machine than the PET"
        end

        # BASIC 2 and 4 load the first program off the disk and run it.
        # BASIC 1's LOAD finds no device on the IEEE-488 bus, so the first
        # program, which the block gives, goes in as a program file does,
        # once the KERNAL has booted. The SuperPET's 6809 starts its own
        # menu instead.
        def disk_autostart(machine)
          return unless machine.boots_basic?
          return machine.type_text(AUTOSTART) unless machine.model.basic1?

          data = yield
          machine.on_init { Program.load(machine, data, autostart: true) } if data
        end
      end
    end
  end
end
