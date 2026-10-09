# frozen_string_literal: true

module Badline
  class C128
    class Bus
      # What the Z80 sees, in memory and through IN and OUT, laid over the
      # 8502's map whenever the MMU, the port or a cartridge changes it
      # while the Z80 has the bus.
      #
      # In C128 mode, with CR's RAM bank 0, the MMU translates $0000-$0FFF
      # to $D000-$DFFF of bank 0: a read gets the Z80 BIOS, which the
      # KERNAL ROM holds there, and a write or an IN or OUT the RAM at
      # $Dxxx. With bank 1 those pages are RAM, common RAM's or bank 1's.
      # $D000-$DFFF is RAM. In C64 mode the PLA decodes the Z80's memory
      # accesses as it does the 8502's.
      #
      # In both modes the chips at $D000-$DFFF answer IN and OUT whether
      # I/O is mapped in or not. The MMU's registers at $D500 take an OUT
      # either way in C128 mode, but answer an IN only with CR's I/O bit
      # on, memory answering it otherwise. While I/O is mapped in, the colour RAM
      # the 8502 sees also answers at $1000-$13FF. An IN or OUT anywhere
      # else reaches what memory has there.
      module Z80Pages
        # A page seen at another address: the address's bits in +mask+ from
        # +base+ on.
        class Window
          def initialize(target, base, mask)
            @target = target
            @base = base
            @mask = mask
          end

          def peek(addr) = @target.peek(@base | (addr & @mask))
          def poke(addr, value) = @target.poke(@base | (addr & @mask), value)
        end

        # The Z80's memory and I/O pages, each 256 entries.
        attr_reader :z80_read_pages, :z80_write_pages, :z80_input_pages, :z80_output_pages

        # Calls the block whenever MCR bit 0 hands the bus to the other CPU.
        def on_processor_change(&block)
          @on_processor_change = block
        end

        # Whether the Z80 has the bus, MCR bit 0 low.
        def z80? = @z80

        private

        # Lays out the Z80's pages again while it has the bus, and tells the
        # machine if MCR bit 0 handed the bus over.
        def update_z80!
          z80 = @mmu.z80?
          map_z80_pages if z80
          return if z80 == @z80

          @z80 = z80
          @on_processor_change&.call
        end

        def build_z80_pages
          @z80_bios = ROM.new(ROM.read("c128/kernal.rom")[0x1000, 0x1000], length: 0x1000, start: 0)
          @z80_read_pages = Array.new(256)
          @z80_write_pages = Array.new(256)
          @z80_input_pages = Array.new(256)
          @z80_output_pages = Array.new(256)
          @z80_color_ram = [Window.new(@color_lines.color_ram(0), 0xd800, 0x3ff),
                            Window.new(@color_lines.color_ram(1), 0xd800, 0x3ff)]
          @z80_translated = Window.new(@ram, 0xd000, 0xfff)
          @z80 = @mmu.z80?
          @on_processor_change = nil
        end

        def map_z80_pages
          c128_mode = !@mmu.c64_mode?
          bios = c128_mode && @mmu.cr < 0x40
          @z80_read_pages.replace(@read_pages)
          @z80_write_pages.replace(@write_pages)
          map_z80_ram_pages if c128_mode
          map_z80_bios if bios
          map_z80_color_ram(c128_mode) if @io_mapped
          @z80_input_pages.replace(@z80_read_pages)
          @z80_output_pages.replace(@z80_write_pages)
          @z80_input_pages.fill(@z80_translated, 0, 16) if bios
          @io_mapped ? map_z80_io_from_cpu : map_z80_io
        end

        def map_z80_ram_pages
          (0xd0..0xdf).each do |page|
            ram = bank_of(page, @mmu.cpu_bank).zero? ? @ram : @bank1
            @z80_read_pages[page] = @z80_write_pages[page] = ram
          end
        end

        def map_z80_bios
          @z80_read_pages.fill(@z80_bios, 0, 16)
          @z80_write_pages.fill(@z80_translated, 0, 16)
        end

        def map_z80_color_ram(c128_mode)
          window = @z80_color_ram[c128_mode ? @io_port.value & 0x01 : 1]
          @z80_read_pages.fill(window, 0x10, 4)
          @z80_write_pages.fill(window, 0x10, 4)
        end

        def map_z80_io_from_cpu
          (0xd0..0xdf).each do |page|
            @z80_input_pages[page] = @read_pages[page]
            @z80_output_pages[page] = @write_pages[page]
          end
        end

        # The chips at $D000-$DFFF while I/O is mapped out, leaving an IN
        # at $D500 to memory.
        def map_z80_io
          lay_out_io(@z80_input_pages, @z80_output_pages)
          @z80_output_pages[0xd5] = @mmu unless @mmu.c64_mode?
        end
      end
    end
  end
end
