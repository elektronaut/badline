# frozen_string_literal: true

module Badline
  class C128
    class Bus
      # What the MMU maps. For the CPU: the RAM bank, common RAM and the
      # pages page 0 and page 1 move to in both modes, and CR's ROMs and I/O
      # in C128 mode. C64 mode lays the PLA's ROMs and I/O over the same RAM
      # (AddressBus::PLA).
      module MMUPages
        private

        # CR's ROMs and I/O over the RAM, with the configuration registers on
        # top at $FF00.
        def map_c128_pages
          cr = @mmu.cr
          map_ram_pages
          @read_pages.fill(@basic_low_rom, 0x40, 0x40) if cr.nobits?(0x02)
          map_rom_block((cr >> 2) & 0x03, 0x80)
          map_rom_block((cr >> 4) & 0x03, 0xc0)
          map_io_pages if cr.nobits?(0x01)
          @configuration_reads.below = @read_pages[0xff]
          @configuration_writes.below = @write_pages[0xff]
          @read_pages[0xff] = @configuration_reads
          @write_pages[0xff] = @configuration_writes
        end

        # A 16K block's two CR bits pick the system ROM, the internal or the
        # external function ROM, neither of which is fitted, or RAM.
        def map_rom_block(select, first_page)
          case select
          when 0 then map_system_rom(first_page)
          when 1, 2 then @read_pages.fill(@open_bus, first_page, 0x40)
          end
        end

        # BASIC's high half at $8000, or the screen editor, the character ROM
        # and the KERNAL at $C000.
        def map_system_rom(first_page)
          if first_page == 0x80
            @read_pages.fill(@basic_high_rom, 0x80, 0x40)
          else
            @read_pages.fill(@editor_rom, 0xc0, 0x10)
            @read_pages.fill(@c128_character_rom, 0xd0, 0x10)
            @read_pages.fill(@c128_kernal_rom, 0xe0, 0x20)
          end
        end

        # The bank CR picks, with common RAM in bank 0, then the pages page 0
        # and page 1 move to.
        def map_ram_pages
          @io_mapped = false
          bank_ram = @mmu.cpu_bank.zero? ? @ram : @bank1
          @read_pages.fill(bank_ram)
          @write_pages.fill(bank_ram)
          map_common_ram
          relocate_pages
        end

        def map_common_ram
          low = @mmu.common_low_pages
          high = @mmu.common_high_start
          @read_pages.fill(@ram, 0, low)
          @write_pages.fill(@ram, 0, low)
          @read_pages.fill(@ram, high, 256 - high)
          @write_pages.fill(@ram, high, 256 - high)
        end

        # In C128 mode page 0 and page 1 go to the pages P0 and P1 name, in
        # bank 0 if common RAM holds them. In both modes, the page each moved
        # to reaches back to page 0 or page 1, in the bank it named, if the
        # CPU sees that bank there. Page 1's takes the page they both name.
        # C64 mode moves neither page 0 nor page 1 forward, so either can be
        # the page that reaches back.
        def relocate_pages
          mmu = @mmu
          forward = !mmu.c64_mode?
          if forward
            map_relocated(0, @relocated[0], bank_of(0, mmu.p0_bank), mmu.p0_page)
            map_relocated(1, @relocated[1], bank_of(1, mmu.p1_bank), mmu.p1_page)
          end
          reach_back(@relocated[2], mmu.p0_page, mmu.p0_bank, 0, forward)
          reach_back(@relocated[3], mmu.p1_page, mmu.p1_bank, 1, forward)
        end

        def reach_back(window, page, bank, home, forward)
          return if forward && page < 2
          return unless bank_of(page, @mmu.cpu_bank) == bank

          map_relocated(page, window, bank, home)
        end

        def map_relocated(page, window, bank, target)
          window.base = (bank << 16) | (target << 8)
          @read_pages[page] = @write_pages[page] = window
        end

        # The bank +page+ reaches when the CPU or a pointer asks for +bank+.
        def bank_of(page, bank)
          page < @mmu.common_low_pages || page >= @mmu.common_high_start ? 0 : bank
        end
      end
    end
  end
end
