# frozen_string_literal: true

module Badline
  class C128
    # The three keys outside the keyboard matrix: RESTORE, CAPS LOCK and
    # 40/80 DISPLAY.
    module Keys
      # RESTORE pulses NMI for a cycle, as on the C64.
      def press_restore
        @restore_pulse = true
      end

      def release_restore; end

      # CAPS LOCK locks down and up, and holds the 8502's P6 low while down.
      def press_caps_lock
        @bus.caps_lock = true
      end

      def release_caps_lock
        @bus.caps_lock = false
      end

      # The 40/80 DISPLAY key locks down and up. The KERNAL reads it at reset
      # and starts the screen editor on the VDC's 80 columns while it is down.
      def press_display_key
        @bus.mmu.display_key = true
      end

      def release_display_key
        @bus.mmu.display_key = false
      end
    end
  end
end
