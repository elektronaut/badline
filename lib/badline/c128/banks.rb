# frozen_string_literal: true

module Badline
  class C128
    # The RAM the C128 KERNAL's bank numbers 0-15 reach, as its INDFET and
    # INDSTA reach it for LOAD, SAVE and the file name: the RAM bank of the
    # CR value the KERNAL's table at $F7F0 holds for the bank, with common
    # RAM in bank 0. The ROMs and I/O some of those CR values map are left
    # out.
    class Banks
      CONFIGURATIONS = 0xf7f0

      def initialize(ram, mmu, kernal_rom)
        @ram = ram
        @mmu = mmu
        @kernal_rom = kernal_rom
      end

      def peek(bank, addr) = @ram.peek(physical(bank, addr))

      def write(bank, addr, bytes)
        bytes.each_with_index { |byte, i| @ram.poke(physical(bank, (addr + i) & 0xffff), byte) }
      end

      private

      def physical(bank, addr)
        page = addr >> 8
        common = page < @mmu.common_low_pages || page >= @mmu.common_high_start
        ram_bank = common ? 0 : (@kernal_rom.peek(CONFIGURATIONS + (bank & 0x0f)) >> 6) & 0x01
        (ram_bank << 16) | addr
      end
    end
  end
end
