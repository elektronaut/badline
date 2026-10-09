# frozen_string_literal: true

require "badline/z80/core"

module Badline
  class C128
    # The C128's Z80A, on the Z80's side of the C128::Bus.
    class Z80
      include Badline::Z80::Core
    end

    # The Z80's accesses, through the pages C128::Bus lays out for it
    # (Bus::Z80Pages). An IN or OUT first brings the chips up to the cycle
    # it falls in, since the Z80 runs whole instructions ahead of them.
    class Z80Bus
      def initialize(bus)
        @read_pages = bus.z80_read_pages
        @write_pages = bus.z80_write_pages
        @input_pages = bus.z80_input_pages
        @output_pages = bus.z80_output_pages
        @machine = nil
      end

      # The machine whose chips an IN or OUT catches up.
      attr_writer :machine

      def fetch(addr) = @read_pages[addr >> 8].peek(addr)

      def read(addr) = @read_pages[addr >> 8].peek(addr)

      def write(addr, value)
        @write_pages[addr >> 8].poke(addr, value)
      end

      def input(port)
        @machine.z80_catch_up
        @input_pages[port >> 8].peek(port)
      end

      def output(port, value)
        @machine.z80_catch_up
        @output_pages[port >> 8].poke(port, value)
      end

      # Nothing drives the data bus in an interrupt acknowledge cycle.
      def acknowledge = 0xff
    end
  end
end
