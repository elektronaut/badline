# frozen_string_literal: true

module Badline
  module Chips
    class PIA
      class ControlLines
        # A side's control register, its lines' levels, its flags and the
        # handshake or pulse under way, under `prefix`. The level driven on
        # C2 follows from them on load.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}control", @control).bool("#{prefix}c1_high", @c1_high).bool("#{prefix}c2_high", @c2_high)
            out.bool("#{prefix}c1_flag", @c1_flag).bool("#{prefix}c2_flag", @c2_flag)
            out.bool("#{prefix}handshake_low", @handshake_low).int("#{prefix}pulse", @pulse)
          end

          def load_fields(input, prefix)
            @control = input.masked("#{prefix}control", @control, 0x3f)
            @c1_high = input.bool("#{prefix}c1_high", @c1_high)
            @c2_high = input.bool("#{prefix}c2_high", @c2_high)
            @c1_flag = input.bool("#{prefix}c1_flag", @c1_flag)
            @c2_flag = input.bool("#{prefix}c2_flag", @c2_flag)
            @handshake_low = input.bool("#{prefix}handshake_low", @handshake_low)
            @pulse = input.masked("#{prefix}pulse", @pulse, 0x03)
            drive
          end
        end

        include KeyedState
      end

      # The PIA's fields in a keyed snapshot module (Snapshot::Keyed): the
      # output and direction registers, and each side's control lines under
      # ca. and cb. The peripheral restores its own state.
      module KeyedState
        def save_fields(out)
          out.int("ora", @ora).int("orb", @orb).int("ddra", @ddra).int("ddrb", @ddrb)
          @ca.save_fields(out, "ca.")
          @cb.save_fields(out, "cb.")
          out
        end

        def load_fields(input)
          @ora = input.byte("ora", @ora)
          @orb = input.byte("orb", @orb)
          @ddra = input.byte("ddra", @ddra)
          @ddrb = input.byte("ddrb", @ddrb)
          @ca.load_fields(input, "ca.")
          @cb.load_fields(input, "cb.")
        end
      end

      include KeyedState
    end
  end
end
