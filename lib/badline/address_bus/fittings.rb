# frozen_string_literal: true

module Badline
  class AddressBus
    # What a model fits around the chips: its KERNAL, a datasette or none,
    # and the board and case they sit in.
    module Fittings
      # The keywords #fit takes.
      NAMES = %i[kernal datasette board].freeze

      # The C64's board and case, the PET 64's, whose built-in monitor
      # shows the VIC's output in shades of green, or the C64GS's, which
      # has no keyboard.
      BOARDS = %i[c64 pet64 gs].freeze

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
      end
    end
  end
end
