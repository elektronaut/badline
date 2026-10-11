# frozen_string_literal: true

module Badline
  module Media
    # What the 264 series does with media of its own (Media.attach).
    module Plus4Media
      # The platform byte of a C16 or Plus/4 tape (Storage::TAP#platform).
      TAPE_PLATFORM = 2

      class << self
        # A tape made for another machine plays all the same, and says so.
        def tape_message(tape, message)
          tape.platform == TAPE_PLATFORM ? message : "#{message}, a tape for another machine than the Plus/4"
        end
      end
    end
  end
end
