# frozen_string_literal: true

module Badline
  class CBM2
    # The B series' 6551 at $DD00, the RS-232 port's, whose IRQ reaches
    # TPI1's I4.
    class ACIA < Chips::ACIA
    end
  end
end
