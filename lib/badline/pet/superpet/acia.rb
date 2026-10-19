# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The board's 6551 at $EFF0, the RS-232 port's, on a 1.8432 MHz
      # crystal, whose IRQ joins the PET's.
      class ACIA < Chips::ACIA
      end
    end
  end
end
