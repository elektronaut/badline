# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # The 6510T's port at $00 (direction) and $01 (data), wired to the
      # mechanism in the bits of the 1541's VIA 2 port B (zimmers.net's 1551
      # memory map, schematic 251860):
      #
      #   P0-1  stepper phase (out)       P4    write protect (in, 1 = writable)
      #   P2    motor on (out)            P5-6  bit rate, speed zone 0-3 (out)
      #   P3    activity LED (out)        P7    BYTE LATCHED (in)
      #
      # An output pin reads back what it drives, and a pin left as an input
      # drives nothing into the mechanism.
      class Port
        WRITE_PROTECT = 0x10
        BYTE_LATCHED = 0x80

        attr_reader :ddr, :data

        def initialize(mechanism)
          @mechanism = mechanism
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

          ddr = @ddr
          (@data & ddr) | (inputs & ~ddr & 0xff)
        end

        def poke(addr, value)
          if addr.zero?
            @ddr = value
          else
            @data = value
          end
          changed
        end

        # The registers, in a keyed snapshot module (BL-D8-PORT).
        def save_fields(out)
          out.int("ddr", @ddr).int("data", @data)
        end

        def load_fields(input)
          @ddr = input.byte("ddr", @ddr)
          @data = input.byte("data", @data)
        end

        private

        def inputs
          mechanism = @mechanism
          value = (mechanism.read_b(0xff) & WRITE_PROTECT) | (0xff & ~(WRITE_PROTECT | BYTE_LATCHED))
          mechanism.byte_latched? ? value | BYTE_LATCHED : value
        end

        def changed
          @mechanism.port_b_written(@data & @ddr)
        end
      end
    end
  end
end
