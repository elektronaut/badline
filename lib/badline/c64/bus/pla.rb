# frozen_string_literal: true

module Badline
  class AddressBus
    # The C64's PLA: what each page of the CPU's view maps to, from the
    # CPU port's LORAM, HIRAM and CHAREN lines and the cartridge's EXROM
    # and GAME. The bus that includes it supplies the page tables, the
    # ROMs, the chips, #map_ram_pages, which lays out the RAM that the
    # ROMs, the cartridge and I/O map over, and #map_io_pages, which lays
    # out the chips at $D000-$DFFF, with #map_cartridge_io for I/O 1 and 2.
    module PLA
      # A chip's registers seen at another page, which reads and writes
      # them as at the page the chip starts at.
      class Mirror
        def initialize(chip, start)
          @chip = chip
          @start = start
        end

        def peek(addr) = @chip.peek(@start | (addr & 0xff))
        def poke(addr, value) = @chip.poke(@start | (addr & 0xff), value)
      end

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

      # Ultimax mode ignores the $01 lines: 4K of RAM, ROML/ROMH windows,
      # I/O always visible and open address space everywhere else. The ROML
      # and ROMH selects fire on writes as well, so cartridge RAM or flash in
      # either window takes the writes there. The MAX has 2K of RAM, and is
      # in Ultimax mode with no cartridge too.
      def map_ultimax_pages
        first = @board == :max ? 0x08 : 0x10
        @read_pages.fill(@open_bus, first, 0x100 - first)
        @write_pages.fill(@open_bus, first, 0x100 - first)
        map_ultimax_cartridge if @cartridge
        map_io_pages
        map_max_io if @board == :max
      end

      def map_ultimax_cartridge
        @read_pages.fill(@cartridge.roml, 0x80, 0x20) if @cartridge.roml
        map_ultimax_writes(@cartridge.roml, 0x80)
        @read_pages.fill(@cartridge.romh, 0xe0, 0x20) if @cartridge.romh
        map_ultimax_writes(@cartridge.romh, 0xe0)
        map_ultimax_a000
      end

      def map_ultimax_writes(bank, first_page)
        @write_pages.fill(bank, first_page, 0x20) if bank.respond_to?(:poke)
      end

      def map_ultimax_a000
        return unless (window = @cartridge.ultimax_a000)

        @read_pages.fill(window, 0xa0, 0x20)
        @write_pages.fill(window, 0xa0, 0x20)
      end

      # The MAX has no CIA 2 and no I/O 2: CIA 1 answers all through
      # $DC00-$DFFF, but for the I/O 1 page a cartridge takes.
      def map_max_io
        @cia1_mirror ||= Mirror.new(cia1, 0xdc00)
        (0xdd..0xdf).each { |page| @read_pages[page] = @write_pages[page] = @cia1_mirror }
        return unless @cartridge

        @write_pages[0xde] = @cartridge
        @read_pages[0xde] = @cartridge if @cartridge.readable_io_pages.include?(0xde)
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
