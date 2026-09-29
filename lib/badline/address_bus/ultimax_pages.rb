# frozen_string_literal: true

module Badline
  class AddressBus
    # The page tables of an Ultimax cartridge, which AddressBus lays out
    # in place of the $01 banking while the cartridge holds GAME low and
    # EXROM high.
    module UltimaxPages
      private

      # Ultimax cartridges ignore the $01 lines: 4K of RAM, ROML/ROMH windows,
      # I/O always visible and open address space everywhere else. The ROML
      # and ROMH selects fire on writes as well, so cartridge RAM or flash in
      # either window takes the writes there.
      def map_ultimax_pages
        @read_pages.fill(@open_bus, 0x10, 0xf0)
        @write_pages.fill(@open_bus, 0x10, 0xf0)
        @read_pages.fill(@cartridge.roml, 0x80, 0x20) if @cartridge.roml
        map_ultimax_writes(@cartridge.roml, 0x80)
        @read_pages.fill(@cartridge.romh, 0xe0, 0x20) if @cartridge.romh
        map_ultimax_writes(@cartridge.romh, 0xe0)
        map_ultimax_a000
        map_io_pages
      end

      def map_ultimax_writes(bank, first_page)
        @write_pages.fill(bank, first_page, 0x20) if bank.respond_to?(:poke)
      end

      def map_ultimax_a000
        return unless (window = @cartridge.ultimax_a000)

        @read_pages.fill(window, 0xa0, 0x20)
        @write_pages.fill(window, 0xa0, 0x20)
      end
    end
  end
end
