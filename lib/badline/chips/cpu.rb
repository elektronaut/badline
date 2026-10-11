# frozen_string_literal: true

require "badline/chips/cpu/core"

module Badline
  module Chips
    # The C64's 6510, on the AddressBus.
    class CPU
      include Core
    end
  end
end
