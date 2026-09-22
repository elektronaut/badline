# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # Mid-line writes to the sprite registers, keyed by the pixel at which
    # they become visible. Compositing replays the line through the log, so
    # each pixel is drawn with the register values that were in effect when
    # the VIC reached it.
    class RegisterLog
      def initialize(registers)
        @registers = registers
        @entries = []
        @seed = []
        @values = Array.new(2**6, 0)
        @cursor = 0
        @next_x = 0
      end

      # The pixel at which the next logged write takes effect.
      attr_reader :next_x

      def empty? = @entries.empty?
      def length = @entries.length

      def clear
        return if @entries.empty?

        @entries.clear
        @seed.clear
      end

      def log(pixel_x, reg, old, value)
        @seed[reg] = old if @seed[reg].nil?
        @entries << [pixel_x, reg, value]
      end

      def prepare
        @entries.sort_by! { |entry| entry[0] }
      end

      # Restart the cursor before the line's first pixel, with every logged
      # register back at the value it held when the line started.
      def rewind
        @values.length.times { |reg| @values[reg] = @registers[reg] }
        @seed.each_with_index { |value, reg| @values[reg] = value unless value.nil? }
        @cursor = 0
        @next_x = @entries.empty? ? Float::INFINITY : @entries[0][0]
      end

      def [](reg) = @values[reg]

      # Apply every write visible at or before pixel_x.
      def advance(pixel_x)
        while @cursor < @entries.length && @entries[@cursor][0] <= pixel_x
          entry = @entries[@cursor]
          @values[entry[1]] = entry[2]
          @cursor += 1
        end
        @next_x = @cursor < @entries.length ? @entries[@cursor][0] : Float::INFINITY
      end
    end
  end
end
