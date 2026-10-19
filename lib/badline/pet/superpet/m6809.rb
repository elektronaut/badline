# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The board's 6809E, on the PET's bus, as the 6502 is.
      class M6809
        include Chips::M6809::Core
      end
    end
  end
end
