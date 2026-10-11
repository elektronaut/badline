# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's colours, which its window and views share, from the
    # C64's palette: one for each voice, and light blue on blue as on the
    # machine's screen.
    module PlayerTheme
      TEXT = Chips::VIC::PALETTE[14]
      BRIGHT = Chips::VIC::PALETTE[1]
      DIM = Chips::VIC::PALETTE[11]
      BOX = Chips::VIC::PALETTE[0]
      BACKGROUND = Chips::VIC::PALETTE[6]
      WARNING = Chips::VIC::PALETTE[10]
      VOICE_COLORS = [Chips::VIC::PALETTE[7], Chips::VIC::PALETTE[13], Chips::VIC::PALETTE[3]].freeze
    end
  end
end
