# frozen_string_literal: true

module Badline
  module Chips
    class TPI
      # The registers, the interrupt latches, mask and AIR, the priority
      # stack, CA and CB, and the levels on the interrupt inputs, in a
      # keyed snapshot module (BL-TPI1 and BL-TPI2).
      module KeyedState
        def save_fields(out)
          out.ints("ports", [@pra, @prb, @prc]).ints("directions", [@ddra, @ddrb, @ddrc])
          out.int("control", @control).int("latches", @latches).int("mask", @mask).int("air", @air)
          out.ints("stack", @stack).bool("ca", @ca).bool("cb", @cb).int("lines", @lines)
        end

        def load_fields(input)
          ports = input.ints_into("ports", [@pra, @prb, @prc])
          @pra = ports[0] & 0xff
          @prb = ports[1] & 0xff
          @prc = ports[2] & 0xff
          directions = input.ints_into("directions", [@ddra, @ddrb, @ddrc])
          @ddra = directions[0] & 0xff
          @ddrb = directions[1] & 0xff
          @ddrc = directions[2] & 0xff
          @control = input.byte("control", @control)
          @latches = input.masked("latches", @latches, 0x1f)
          @mask = input.masked("mask", @mask, 0x1f)
          @air = input.masked("air", @air, 0x1f)
          @stack.replace(input.ints("stack", []).last(STACK_DEPTH).map { |value| value & 0x1f })
          @ca = input.bool("ca", @ca)
          @cb = input.bool("cb", @cb)
          @lines = input.masked("lines", @lines, 0x1f)
        end
      end

      include KeyedState
    end
  end
end
