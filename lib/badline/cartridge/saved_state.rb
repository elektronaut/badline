# frozen_string_literal: true

module Badline
  class Cartridge
    # A cartridge's state for a snapshot: the setup that builds it again and
    # the state that goes into it.
    module SavedState
      # What builds the same cartridge afresh (Cartridge.from_setup): the CRT
      # image it was built from, and the jumpers of a mapper that has them.
      def save_setup(out)
        out.int(CRT_SETUP).string(Storage::CRTFile.encode(@crt))
        save_jumpers(out)
      end

      # The lines, the pull on NMI, the button and the mapper's own state.
      # Loading sets them without calling back into the machine, which maps
      # the cartridge again afterwards.
      def save_state(out)
        out.marker("CARTRIDGE")
        out.int(@exrom).int(@game).boolean(@nmi).boolean(@button == true)
        save_mapper(out)
      end

      def load_state(input)
        input.marker("CARTRIDGE")
        @exrom = input.int
        @game = input.int
        @nmi = input.boolean?
        @button = input.boolean?
        load_mapper(input)
      end

      private

      def save_jumpers(out)
        out.boolean(false)
      end

      # The mapper's own state: where its windows point, for a mapper that
      # moves them, and whatever a mapper adds after calling super.
      def save_mapper(out)
        save_windows(out, windows) if windows
      end

      def load_mapper(input)
        load_windows(input, windows) if windows
      end

      # Where the ROML and ROMH windows point, as their places in `windows`,
      # the banks and views the mapper picks them from, or -1 for none.
      def save_windows(out, windows)
        out.int(window_index(@roml, windows)).int(window_index(@romh, windows))
      end

      def load_windows(input, windows)
        @roml = window_at(input.int, windows)
        @romh = window_at(input.int, windows)
      end
    end
  end
end
