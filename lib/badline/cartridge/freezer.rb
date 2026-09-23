# frozen_string_literal: true

module Badline
  class Cartridge
    # The freeze button of a freezer cartridge. A press pulls NMI, and the
    # computer calls #freeze! once the CPU has pushed the return address and
    # status of the interrupt, so the vector fetch that follows reads the
    # cartridge ROM in Ultimax mode. The cartridge lets go of NMI when its
    # software acknowledges the freeze.
    module Freezer
      def press_button
        @button = true
        self.nmi = true if freeze_allowed?
      end

      def release_button
        @button = false
      end

      private

      def freeze_allowed?
        true
      end

      def button_pressed?
        @button == true
      end
    end
  end
end
