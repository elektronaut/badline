# frozen_string_literal: true

require "badline/z80/core"

module Badline
  # The Zilog Z80 (NMOS), which the C128 has beside its 8502. It is not
  # part of badline/core, so a machine that has one requires it.
  class Z80
    include Core
  end
end
