# frozen_string_literal: true

module Badline
  module Media
    # What a CBM-II does with media of its own (Media.attach). Disks of
    # every kind, .d80 and .d82 among them, directories and .t64 archives
    # mount on device 8 through the traps on the KERNAL's IEEE-488
    # primitives (CBM2::IEEETraps), programs load into BASIC's text segment
    # (Program), and a CBM2 .crt's ROMs go in at their load addresses in
    # segment 15. There is no datasette, the SID plays no .sid tunes, and
    # the true drives are serial ones.
    module CBM2Media
      # What a CBM-II doesn't take.
      UNSUPPORTED = Extensions.of(%i[tune tape gcr])

      # What loads and runs the first program on the disk in device 8.
      AUTOSTART = %(load"*",8\rrun\r)

      # Where BASIC's text starts in segment 1, and the pointers to its end
      # and to the KERNAL's end address (EAL) in segment 15.
      BASIC_START = 0x0003
      TEXT_END = 0x2f
      EAL = 0x96

      # The ROM chips of a CBM2 .crt.
      def self.cartridge_chips(path) = Storage::CRTFile.new(path, machine: :cbm2).chips
    end
  end
end
