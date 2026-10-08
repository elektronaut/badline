# frozen_string_literal: true

module Badline
  class AddressBus
    # The C64's PLA: what each page of the CPU's view maps to, from the
    # CPU port's LORAM, HIRAM and CHAREN lines and the cartridge's EXROM
    # and GAME. The bus that includes it supplies the page tables, the
    # ROMs, the chips, and #map_ram_pages, which lays out the RAM that the
    # ROMs, the cartridge and I/O map over.
    module PLA
      private

      def map_pla_pages
        map_ram_pages
        @ultimax ? map_ultimax_pages : map_banked_pages
      end

      def map_banked_pages
        map_rom_overlays
        map_cartridge_ram
        @write_pages.fill(@cartridge.romh_writes, 0xe0, 0x20) if @cartridge&.romh_writes

        if io?
          map_io_pages
        elsif character?
          @read_pages.fill(character_rom, 0xd0, 0x10)
        end
      end

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

      # EXROM and GAME select the cartridge whether or not it has a chip
      # there, and an empty socket leaves the bus floating.
      def map_rom_overlays
        @read_pages.fill(@cartridge.roml || @open_bus, 0x80, 0x20) if roml?
        if romh?
          @read_pages.fill(@cartridge.romh || @open_bus, 0xa0, 0x20)
        elsif basic?
          @read_pages.fill(basic_rom, 0xa0, 0x20)
        end
        @read_pages.fill(kernal_rom, 0xe0, 0x20) if kernal?
      end

      # Cartridge RAM in the ROML or ROMH window decodes writes itself,
      # whatever the $01 lines say.
      def map_cartridge_ram
        return unless @cartridge&.exrom&.zero?

        map_cartridge_ram_bank(@cartridge.roml, 0x80)
        map_cartridge_ram_bank(@cartridge.romh, 0xa0) if @cartridge.game.zero?
      end

      def map_cartridge_ram_bank(bank, first_page)
        @write_pages.fill(bank, first_page, 0x20) if bank.is_a?(Cartridge::RAMBank)
      end

      def map_io_pages
        {
          vic => 0xd0..0xd3, sid => 0xd4..0xd7, color_ram => 0xd8..0xdb,
          cia1 => 0xdc..0xdc, cia2 => 0xdd..0xdd, @open_bus => 0xde..0xdf
        }.each do |chip, pages|
          pages.each { |p| @read_pages[p] = @write_pages[p] = chip }
        end
        @ram_expansion.map_io(@read_pages, @write_pages)
        @read_pages[0xd7] = @write_pages[0xd7] = @debug_register if @debug_register
        @read_pages[0xdf] = @write_pages[0xdf] = @reu if @reu
        map_cartridge_io if @cartridge
        map_extra_sids unless @sid_slots.empty?
      end

      def map_cartridge_io
        @write_pages.fill(@cartridge, 0xde, 2)
        @cartridge.readable_io_pages.each { |p| @read_pages[p] = @cartridge }
      end

      def basic?
        io_port.kernal? && io_port.basic? && game_high?
      end

      def game_high?
        @cartridge.nil? || @cartridge.game == 1
      end

      def roml?
        @cartridge&.exrom&.zero? && io_port.kernal? && io_port.basic?
      end

      def romh?
        @cartridge&.exrom&.zero? && @cartridge.game.zero? && io_port.kernal?
      end

      # In 16K mode LORAM alone leaves $d000 as RAM, where it still maps I/O.
      def character?
        (io_port.kernal? || (io_port.basic? && game_high?)) && !io_port.io?
      end

      def io?
        (io_port.basic? || io_port.kernal?) && io_port.io?
      end

      def kernal?
        io_port.kernal?
      end
    end
  end
end
