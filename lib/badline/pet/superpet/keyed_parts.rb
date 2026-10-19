# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      class Board
        # The latches, the socket bit and the 64K of bank RAM, in a keyed
        # snapshot module (BL-SUPERPET). The switches come with the setup
        # (Snapshot::PETSetup). Which CPU has the bus, and the diagnostic
        # sense line, follow from the latches once loaded, and the pages
        # are laid out again (#restored!).
        module KeyedState
          def save_fields(out)
            out.int("bank_latch", @bank_latch).int("system_latch", @system_latch).int("socket", @socket)
            out.bytes("ram", @cells)
          end

          def load_fields(input)
            @bank_latch = input.byte("bank_latch", 0)
            @system_latch = input.byte("system_latch", 0)
            @socket = input.int("socket", 0) & 0x01
            input.bytes_into("ram", @cells)
            @m6809 = m6809_selected?
            @keyboard_ports.diagnostic_low = @system_latch.anybits?(0x08)
          end

          def restored! = @bus.map_pages
        end

        include KeyedState
      end

      class Dongle
        # The shift registers, the latch and a shift waiting, as the cycles
        # from now to the one it ends, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.ints("#{prefix}registers", @registers).int("#{prefix}latch", @latch)
            out.optional_int("#{prefix}shift_in", @shift_at == NONE ? nil : @shift_at - @clock.cycles)
          end

          def load_fields(input, prefix)
            input.ints_into("#{prefix}registers", @registers)
            @latch = input.byte("#{prefix}latch", 0xff)
            shift_in = input.optional_int("#{prefix}shift_in")
            @shift_at = shift_in.nil? ? NONE : @clock.cycles + shift_in
          end
        end

        include KeyedState
      end

      class WaterlooTraps
        # Whether a served device listens or talks, the channel and the
        # command it was addressed with, and the bytes sent it so far,
        # under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.bool("#{prefix}listening", @listening).bool("#{prefix}talking", @talking)
            out.int("#{prefix}channel", @channel).int("#{prefix}frame", @frame).ints("#{prefix}buffer", @buffer)
          end

          def load_fields(input, prefix)
            @listening = input.bool("#{prefix}listening", false)
            @talking = input.bool("#{prefix}talking", false)
            @channel = input.int("#{prefix}channel", 0) & 0x0f
            @frame = input.byte("#{prefix}frame", 0)
            @buffer = input.ints("#{prefix}buffer", []).map { |byte| byte & 0xff }
          end
        end

        include KeyedState
      end
    end
  end
end
