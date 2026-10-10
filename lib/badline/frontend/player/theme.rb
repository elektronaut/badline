# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's colours, which its window and views share, from the
    # C64's palette: one for each voice, and light blue on blue as on the
    # machine's screen.
    module PlayerTheme
      TEXT = VIC::PALETTE[14]
      BRIGHT = VIC::PALETTE[1]
      DIM = VIC::PALETTE[11]
      BOX = VIC::PALETTE[0]
      BACKGROUND = VIC::PALETTE[6]
      WARNING = VIC::PALETTE[10]
      VOICE_COLORS = [VIC::PALETTE[7], VIC::PALETTE[13], VIC::PALETTE[3]].freeze
    end
  end
end
