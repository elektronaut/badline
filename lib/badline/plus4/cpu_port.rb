# frozen_string_literal: true

module Badline
  class Plus4
    # The 7501's I/O port at $00 (direction) and $01 (data). Its seven
    # pins carry the serial bus and the cassette port, and none of them
    # banks memory:
    #
    # - P0, P1 and P2 drive the serial bus's DATA, CLK and ATN through
    #   inverters, so a 1 pulls the line low, and P1 is the cassette write
    #   line too.
    # - P3 runs the cassette motor while it is low.
    # - P4 reads the cassette read line, P6 the serial CLK line and P7 the
    #   DATA line, 1 while the line is high.
    # - P5 has no pin and reads 1.
    #
    # An output pin reads back what it drives. A pin left as an input reads
    # what drives it from outside, and the serial outputs, P0-P2, float high
    # there, so they pull their lines, as an output of 1 does.
    class CPUPort
      DATA_OUT = 0x01
      CLK_OUT = 0x02
      ATN_OUT = 0x04
      MOTOR = 0x08
      TAPE_READ = 0x10
      CLK_IN = 0x40
      DATA_IN = 0x80

      attr_reader :ddr, :data

      def initialize(serial_bus:, datasette:)
        @serial_bus = serial_bus
        @datasette = datasette
        @ddr = 0
        @data = 0
      end

      def reset!
        @ddr = 0
        @data = 0
        changed
      end

      def peek(addr)
        return @ddr if addr.zero?

        (@data & @ddr) | (inputs & ~@ddr & 0xff)
      end

      def poke(addr, value)
        if addr.zero?
          @ddr = value
        else
          @data = value
        end
        changed
      end

      # The pins' levels as they leave the chip, inputs floating high.
      def levels = (@data & @ddr) | (~@ddr & 0xff)

      # The serial bus lines the port pulls low, as Drives::SerialBus host
      # lines.
      def serial_lines
        out = levels
        lines = 0
        lines |= Drives::SerialBus::HOST_ATN_OUT if out.anybits?(ATN_OUT)
        lines |= Drives::SerialBus::HOST_CLK_OUT if out.anybits?(CLK_OUT)
        lines |= Drives::SerialBus::HOST_DATA_OUT if out.anybits?(DATA_OUT)
        lines
      end

      private

      def inputs
        value = 0x2f
        value |= TAPE_READ if @datasette.read_high?
        low = @serial_bus.low_lines
        value |= CLK_IN unless low.anybits?(Drives::SerialBus::CLK)
        value |= DATA_IN unless low.anybits?(Drives::SerialBus::DATA)
        value
      end

      def changed
        lines = serial_lines
        @serial_bus.host_lines = lines unless lines == @serial_bus.host_lines
        out = levels
        @datasette.motor = out.nobits?(MOTOR)
        @datasette.write_line = out.anybits?(CLK_OUT)
      end
    end
  end
end
