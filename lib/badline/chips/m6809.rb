# frozen_string_literal: true

require "badline/chips/m6809/core"

module Badline
  module Chips
    # The Motorola 6809E, which the SuperPET has beside its 6502. It is not
    # part of badline/core, so a machine that has one requires it.
    class M6809
      include Core
    end
  end
end
