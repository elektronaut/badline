# frozen_string_literal: true

module Badline
  class AddressBus
    # What a model fits around the chips: its KERNAL, a datasette or none,
    # and the board and case they sit in.
    module Fittings
      # The keywords #fit takes.
      NAMES = %i[kernal datasette board].freeze

      # The C64's board and case, the PET 64's, whose built-in monitor
      # shows the VIC's output in shades of green, the C64GS's, which has
      # no keyboard, or the MAX Machine's (:max): 2K of RAM, no ROMs, CIA 1
      # alone at $DC00-$DFFF and the cartridge port in Ultimax mode.
      BOARDS = %i[c64 pet64 gs max].freeze

      attr_reader :board

      # Fits the KERNAL ROM ROMs::KERNALS names, leaves the cassette port
      # empty unless `datasette`, and puts the chips in the board BOARDS
      # names.
      def fit(kernal: :c64, datasette: true, board: :c64)
        self.kernal = kernal unless kernal == :c64
        @datasette.disconnect! unless datasette
        self.board = board unless board == :c64
      end

      def board=(name)
        raise ArgumentError, "no board named #{name}" unless BOARDS.include?(name)

        @board = name
        vic.palette = name == :pet64 ? VIC::GREEN_PALETTE : VIC::PALETTE
        keyboard.connected = name != :gs
        update_overlays!
      end
    end
  end
end
