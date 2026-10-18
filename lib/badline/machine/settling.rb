# frozen_string_literal: true

module Badline
  module Machine
    # Brings the machine to the point a snapshot file is saved at: the main
    # CPU between instructions, or jammed, with no REU transfer holding the
    # bus. C64, Vic20, C128, Plus4 and PET each include it, and answer
    # #settled_for_snapshot? and #settle_chips_for_snapshot, which brings
    # what each chip defers up to the cycle without running one.
    module Settling
      # The cycles settling may run: the longest instruction stretched by
      # the VIC's longest hold on the bus, and an REU swap of 64K, two
      # cycles a byte, stretched the same way.
      LIMIT = 100 + 0x40000

      # Runs the machine on, through its own #cycle!, to the settle point,
      # and returns the cycles that took. A settled machine runs none.
      def settle_for_snapshot!
        ran = 0
        while ran < LIMIT && !settled_for_snapshot?
          cycle!
          ran += 1
        end
        settle_chips_for_snapshot
        ran
      end

      # Settles as #settle_for_snapshot! does, for a snapshot VICE opens,
      # which a machine with a drive VICE runs settles further.
      def settle_for_vice! = settle_for_snapshot!
    end
  end
end
