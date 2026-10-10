# frozen_string_literal: true

require "badline/banked_ram/banking"
require "badline/banked_ram/unexpanded"
require "badline/banked_ram/plus60k"
require "badline/banked_ram/plus256k"

module Badline
  # RAM expansions that bank extra memory in under the CPU through a
  # register at $D100, in the VIC's I/O page. Any write to $D100-$D1FF
  # sets the register, which reads back as $FF.
  module BankedRAM
    TYPES = { plus60k: Plus60k, plus256k: Plus256k }.freeze

    def self.build(type, ram, &)
      expansion = type ? TYPES.fetch(type).new(ram) : Unexpanded.new(ram)
      expansion.on_change(&)
      expansion
    end
  end
end
