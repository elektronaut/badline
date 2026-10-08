# frozen_string_literal: true

module Badline
  class C128
    class VDC
      # The VDC's own DRAM: 16K of two 4416s (16K by 4) or 64K of 4164s or
      # 4464s, behind the 16-bit addresses the VDC computes.
      #
      # The VDC drives an address onto the DRAM's pins as a row and a
      # column, and R28 bit 4 picks the order (Programmer's Reference Guide,
      # R28): set, for 64K parts, the row is A0-A7 and the column A8-A15;
      # clear, for 4416s, the column pins carry A8, A8, A9-A13 and A15, and
      # A14 goes nowhere. A 4416 has only six column lines and ignores the
      # first and the last column pin. That gives the four layouts
      # VDC/vdcdump's patterns.txt records from real machines: a 16K VDC in
      # 64K mode sees A9-A14, so pages p, p ^ 1 and p ^ $80 are one page,
      # and a 64K VDC in 16K mode sees page p at page
      # (p & $80) | (p & $3E) << 1 | (p & 1) * 3.
      class Memory
        attr_reader :ram

        def initialize(ram_kb)
          @ram = Array.new(ram_kb * 1024, 0)
          @layouts = [false, true].map { |mode64| Array.new(256) { |page| page_base(page, mode64) }.freeze }
          @pages = @layouts[0]
        end

        # Selects 64K mode, R28 bit 4, or 16K mode.
        def mode64=(on)
          @pages = @layouts[on ? 1 : 0]
        end

        def fetch(addr) = @ram[@pages[(addr >> 8) & 0xff] | (addr & 0xff)]

        def store(addr, value)
          @ram[@pages[(addr >> 8) & 0xff] | (addr & 0xff)] = value
        end

        def clear!
          @ram.fill(0)
        end

        private

        def page_base(page, mode64)
          pins = mode64 ? page : (page & 0x80) | ((page & 0x3e) << 1) | ((page & 1) * 3)
          return pins << 8 if @ram.length == 0x10000

          ((pins >> 1) & 0x3f) << 8
        end
      end
    end
  end
end
