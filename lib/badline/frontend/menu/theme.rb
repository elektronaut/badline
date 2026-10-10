# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's colours, which its pages and dialogs share. They lie
    # outside the C64's palette, so the menu reads as the emulator's and
    # not the machine's.
    module MenuTheme
      PANEL = 0x1d2230
      EDGE = 0x3a4256
      TEXT = 0xc9d1e0
      BRIGHT = 0xffc66d
      DIM = 0x6b7489
      FILL = 0x343c50
      WARNING = 0xff7a6b
    end
  end
end
