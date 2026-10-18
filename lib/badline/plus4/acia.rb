# frozen_string_literal: true

module Badline
  class Plus4
    # The Plus/4's 6551 at $FD00-$FD0F, on the user port. Nothing drives
    # its RxC pin, and the user port carries no CTS; the KERNAL takes the
    # user port's 6529 P1 as its handshake.
    class ACIA < Chips::ACIA
    end
  end
end
