# frozen_string_literal: true

module Badline
  class PET
    class Bus
      # The 8096's 64K board: four 16K banks, which a write-only control
      # register at $FFF0 lays over $8000-$FFFF, two at a time:
      #
      #   bit 7  the board on; when clear, a plain 8032 and the rest ignored
      #   bit 6  I/O shows through at $E800-$EFFF
      #   bit 5  the screen shows through at $8000-$8FFF
      #   bit 3  bank 3 at $C000-$FFFF, else bank 1
      #   bit 2  bank 2 at $8000-$BFFF, else bank 0
      #   bit 1  writes to $C000-$FFFF go nowhere
      #   bit 0  writes to $8000-$BFFF go nowhere
      #
      # A write to $FFF0 lands where $FFF0 was before it, too. The RES line
      # clears the register, so the 8096 starts as an 8032.
      class Expansion
        # A 16K bank of the board, seen from +start+.
        class Window
          attr_accessor :read_only

          def initialize(cells, offset, start)
            @cells = cells
            @offset = offset - start
            @read_only = false
          end

          def peek(addr) = @cells[addr + @offset]

          def poke(addr, value)
            @cells[addr + @offset] = value unless @read_only
          end
        end

        # Page $FF's writes, which pass to what the page holds and set the
        # control register at $FFF0.
        class ControlPort
          attr_accessor :under

          def initialize(expansion, under)
            @expansion = expansion
            @under = under
          end

          def poke(addr, value)
            @under.poke(addr, value)
            @expansion.control = value if addr == 0xfff0
          end
        end

        attr_reader :cells, :control

        def initialize(bus)
          @bus = bus
          @cells = Array.new(0x10000, 0)
          @banks = [0x8000, 0xc000, 0x8000, 0xc000].each_with_index.map do |start, bank|
            Window.new(@cells, bank * 0x4000, start)
          end
          @port = ControlPort.new(self, @banks[1])
          @control = 0
        end

        def control=(value)
          @control = value
          @bus.map_pages
        end

        def reset!
          self.control = 0
        end

        def power_on!
          @cells.fill(0)
        end

        # Lays the banks the register picks over the pages, and the
        # control register over page $FF's writes.
        def map(reads, writes)
          map_banks(reads, writes) if @control.anybits?(0x80)
          @port.under = writes[0xff]
          writes[0xff] = @port
        end

        private

        def map_banks(reads, writes)
          low = @banks[@control.anybits?(0x04) ? 2 : 0]
          high = @banks[@control.anybits?(0x08) ? 3 : 1]
          low.read_only = @control.anybits?(0x01)
          high.read_only = @control.anybits?(0x02)
          first = @control.anybits?(0x20) ? 0x90 : 0x80
          reads.fill(low, first, 0xc0 - first)
          writes.fill(low, first, 0xc0 - first)
          [[0xc0, 0x28], [0xe8, 0x08], [0xf0, 0x10]].each do |page, count|
            next if page == 0xe8 && @control.anybits?(0x40)

            reads.fill(high, page, count)
            writes.fill(high, page, count)
          end
        end
      end
    end
  end
end
