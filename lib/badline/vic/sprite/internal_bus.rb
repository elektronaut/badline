# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    class Sprite
      # = InternalBus
      #
      # What a sprite's s-accesses read while its DMA is off. The first and
      # third fall in phi2, where the VIC's internal bus floats to $ff unless
      # the CPU reads or writes a VIC register in that cycle, and the middle
      # one is the idle fetch at $3fff (sbsprf24's readme).
      class InternalBus
        def initialize(bank, columns)
          @bank = bank
          @lines = 0
          @ghost = 0xff
          @value = Array.new(columns, 0xff)
          @line = Array.new(columns, -1)
        end

        # Sprites 3-7 fetch in Bauer cycles 1-10, so the idle byte is taken
        # as the line starts.
        def start_line(sprites_enabled)
          @lines += 1
          @ghost = @bank.peek(0x3fff) if sprites_enabled
        end

        # The VIC has advanced to `column`, so the access runs in Bauer cycle
        # `column + 1`, and column 0 is the first cycle of the line about to
        # start.
        def access(column, value)
          @value[column] = value
          @line[column] = column.zero? ? @lines + 1 : @lines
        end

        # The row sprite `index` (3-7) fetched this line, in Bauer cycles
        # 2n-5 and 2n-4.
        def row(index)
          column = (2 * index) - 6
          (phi2(column) << 16) | (@ghost << 8) | phi2(column + 1)
        end

        private

        def phi2(column) = @line[column] == @lines ? @value[column] : 0xff
      end
    end
  end
end
