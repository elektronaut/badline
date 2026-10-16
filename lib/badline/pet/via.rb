# frozen_string_literal: true

module Badline
  class PET
    # The PET's 6522 at $E840, a class of its own so its peripheral keeps
    # one type (PET::VIAPorts), apart from the VIC-20's and the drives'.
    class VIA < Chips::VIA
    end
  end
end
