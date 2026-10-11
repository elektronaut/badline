# frozen_string_literal: true

module Badline
  class C64
    class Cartridge
      class Standard < Cartridge
        private

        def install_chips(chips)
          roml, romh = banks_from(chips)
          @roml = roml.compact.first
          @romh = romh.compact.first
        end
      end
    end
  end
end
