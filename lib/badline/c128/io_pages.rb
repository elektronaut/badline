# frozen_string_literal: true

module Badline
  class C128
    class Bus
      # The chips at $D000-$DFFF, which the 8502 sees while I/O is mapped
      # in and the Z80 reaches through IN and OUT.
      module IOPages
        private

        def map_io_pages
          @io_mapped = true
          lay_out_io(@read_pages, @write_pages)
          @read_pages[0xd5] = @write_pages[0xd5] = @mmu.c64_mode? ? @open_bus : @mmu
          map_cartridge_io if @cartridge
        end

        # The chips into +reads+ and +writes+, but for the MMU's page.
        def lay_out_io(reads, writes)
          reads.fill(@vic, 0xd0, 4)
          writes.fill(@vic_writes, 0xd0, 4)
          reads[0xd4] = writes[0xd4] = @sid
          reads[0xd6] = writes[0xd6] = @vdc
          reads[0xd7] = writes[0xd7] = @debug_page || @open_bus
          reads.fill(@color_ram, 0xd8, 4)
          writes.fill(@color_ram, 0xd8, 4)
          reads[0xdc] = writes[0xdc] = @cia1
          reads[0xdd] = writes[0xdd] = @cia2
          reads.fill(@open_bus, 0xde, 2)
          writes.fill(@open_bus, 0xde, 2)
        end
      end
    end
  end
end
