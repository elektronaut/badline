# frozen_string_literal: true

require "badline/snapshot/c64_setup"
require "badline/snapshot/vic20_setup"
require "badline/snapshot/c128_setup"

module Badline
  module Snapshot
    # How the machine a State was taken of was built, so a machine to
    # restore it into can be built first. A State starts with its family's
    # marker, the stamp (StateWriter#stamp) and the family's setup:
    # C64Setup, Vic20Setup or C128Setup. Each reads its setup from a State
    # (.from) or from the fields after the stamp (.read), writes it
    # (#write), builds a machine that way at power-on (#build) and names it
    # (#to_s).
    module Setup
      # The setup of the family whose marker the State starts with.
      def self.read(state)
        family = StateReader.new(state).string
        return Vic20Setup.from(state) if family == Vic20Setup::MARKER
        return C128Setup.from(state) if family == C128Setup::MARKER

        C64Setup.from(state)
      end

      # A new machine, built as the one a State was taken of, at that
      # state.
      def self.restored(state) = read(state).build.apply_state(state)
    end
  end
end
