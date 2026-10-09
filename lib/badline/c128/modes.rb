# frozen_string_literal: true

module Badline
  class C128
    # Following the MMU between C128 and C64 mode: the KERNAL traps go to
    # the KERNAL the machine runs, and C= held from power-on starts it in C64
    # mode through the C128 KERNAL.
    module Modes
      # Holds C= down from power-on until the C128 KERNAL has taken the
      # machine to C64 mode, as a user does to start a C128 in C64 mode.
      # #on_init's handlers then wait for the C64 KERNAL's boot.
      def hold_commodore_key
        keyboard.press(:cbm)
        @holding_commodore = true
      end

      private

      # The KERNAL the traps stand in for: the C128's in C128 mode, the C64's
      # in C64 mode.
      def trap_layout = mode == :c128 ? KernalTrap::C128_LAYOUT : KernalTrap::C64_LAYOUT

      # The machine went to C64 mode or came back: the traps move to the
      # KERNAL it now runs. C= held from power-on lets go, and #on_init's
      # handlers wait for the C64 KERNAL to boot.
      def mode_changed
        layout = trap_layout
        @capture_output&.layout = layout
        if @drive
          remove_kernal_traps
          install_kernal_traps(layout)
        end
        return unless @holding_commodore && mode == :c64

        keyboard.release(:cbm)
        @holding_commodore = false
        @init_threshold = @cycles + Computer::INIT_THRESHOLD if @cycles < @init_threshold
      end
    end
  end
end
