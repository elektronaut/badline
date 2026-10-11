# frozen_string_literal: true

require "badline/chips/cpu/port"
require "badline/chips/cpu/instruction"
require "badline/chips/cpu/instruction_set"
require "badline/chips/cpu/interrupts"
require "badline/chips/cpu/traps"
require "badline/chips/cpu/core"

module Badline
  module Chips
    # The C64's 6510, on the C64::Bus.
    class CPU
      include Core
    end
  end
end
