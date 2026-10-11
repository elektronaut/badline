# frozen_string_literal: true

module Badline
  module Chips
    class VIA
      class Timer1
        # Timer 1's fields in a keyed snapshot module, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}counter", @counter).int("#{prefix}latch", @latch).bool("#{prefix}hold", @hold)
            out.bool("#{prefix}reload", @reload).bool("#{prefix}armed", @armed).bool("#{prefix}pb7", @pb7)
          end

          def load_fields(input, prefix)
            @counter = input.word("#{prefix}counter", @counter)
            @latch = input.word("#{prefix}latch", @latch)
            @hold = input.bool("#{prefix}hold", @hold)
            @reload = input.bool("#{prefix}reload", @reload)
            @armed = input.bool("#{prefix}armed", @armed)
            @pb7 = input.bool("#{prefix}pb7", @pb7)
          end
        end

        include KeyedState
      end

      class Timer2
        # Timer 2's fields in a keyed snapshot module, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}counter", @counter).int("#{prefix}latch_low", @latch_low).bool("#{prefix}hold", @hold)
            out.bool("#{prefix}low_reload", @low_reload).bool("#{prefix}armed", @armed)
            out.bool("#{prefix}low_underflowed", @low_underflowed).bool("#{prefix}count_pulses", @count_pulses)
            out.bool("#{prefix}counting_pulses", @counting_pulses)
          end

          def load_fields(input, prefix)
            @counter = input.word("#{prefix}counter", @counter)
            @latch_low = input.byte("#{prefix}latch_low", @latch_low)
            @hold = input.bool("#{prefix}hold", @hold)
            @low_reload = input.bool("#{prefix}low_reload", @low_reload)
            @armed = input.bool("#{prefix}armed", @armed)
            @low_underflowed = input.bool("#{prefix}low_underflowed", @low_underflowed)
            @count_pulses = input.bool("#{prefix}count_pulses", @count_pulses)
            @counting_pulses = input.bool("#{prefix}counting_pulses", @counting_pulses)
          end
        end

        include KeyedState
      end

      class ShiftRegister
        # The shift register's fields in a keyed snapshot module, under
        # `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}mode", @mode).int("#{prefix}data", @data).int("#{prefix}bits", @bits)
            out.int("#{prefix}delay", @delay).bool("#{prefix}clock", @clock).bool("#{prefix}cb2", @cb2)
            out.bool("#{prefix}cb2_input", @cb2_input)
          end

          def load_fields(input, prefix)
            @mode = input.masked("#{prefix}mode", @mode, 0x07)
            @data = input.byte("#{prefix}data", @data)
            @bits = input.int("#{prefix}bits", @bits)
            @delay = input.int("#{prefix}delay", @delay)
            @clock = input.bool("#{prefix}clock", @clock)
            @cb2 = input.bool("#{prefix}cb2", @cb2)
            @cb2_input = input.bool("#{prefix}cb2_input", @cb2_input)
          end
        end

        include KeyedState
      end

      class InterruptRegister
        # The flags and the enable mask, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}flags", @flags).int("#{prefix}enable", @enable)
          end

          def load_fields(input, prefix)
            @flags = input.masked("#{prefix}flags", @flags, 0x7f)
            @enable = input.masked("#{prefix}enable", @enable, 0x7f)
          end
        end

        include KeyedState
      end

      class ControlLines
        # A pair of control lines' fields, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}control", @control).bool("#{prefix}c1_high", @c1_high).bool("#{prefix}c2_high", @c2_high)
            out.bool("#{prefix}handshake_low", @handshake_low).int("#{prefix}pulse", @pulse)
            out.bool("#{prefix}c2_output", @c2_output)
          end

          def load_fields(input, prefix)
            @control = input.masked("#{prefix}control", @control, 0x0f)
            @c1_high = input.bool("#{prefix}c1_high", @c1_high)
            @c2_high = input.bool("#{prefix}c2_high", @c2_high)
            @handshake_low = input.bool("#{prefix}handshake_low", @handshake_low)
            @pulse = input.int("#{prefix}pulse", @pulse)
            @c2_output = input.bool("#{prefix}c2_output", @c2_output)
          end
        end

        include KeyedState
      end

      # The VIA's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers and PB6, and its parts under t1., t2., sr., ifr., ca. and
      # cb. Whether the shift register clocks off timer 2 comes from the
      # ACR on load. The peripheral restores its own state.
      module KeyedState
        def save_fields(out)
          out.int("ora", @ora).int("orb", @orb).int("ddra", @ddra).int("ddrb", @ddrb).int("latch_a", @latch_a)
          out.int("latch_b", @latch_b).int("acr", @acr).int("pcr", @pcr).bool("pb6_high", @pb6_high)
          @t1.save_fields(out, "t1.")
          @t2.save_fields(out, "t2.")
          @shift_register.save_fields(out, "sr.")
          @ifr.save_fields(out, "ifr.")
          @ca.save_fields(out, "ca.")
          @cb.save_fields(out, "cb.")
          out
        end

        def load_fields(input)
          @ora = input.byte("ora", @ora)
          @orb = input.byte("orb", @orb)
          @ddra = input.byte("ddra", @ddra)
          @ddrb = input.byte("ddrb", @ddrb)
          @latch_a = input.byte("latch_a", @latch_a)
          @latch_b = input.byte("latch_b", @latch_b)
          @acr = input.byte("acr", @acr)
          @pcr = input.byte("pcr", @pcr)
          @pb6_high = input.bool("pb6_high", @pb6_high)
          load_part_fields(input)
        end

        def restored!
          @sr_uses_t2 = [1, 4, 5].include?((@acr >> 2) & 0x07)
        end

        private

        def load_part_fields(input)
          @t1.load_fields(input, "t1.")
          @t2.load_fields(input, "t2.")
          @shift_register.load_fields(input, "sr.")
          @ifr.load_fields(input, "ifr.")
          @ca.load_fields(input, "ca.")
          @cb.load_fields(input, "cb.")
        end
      end

      include KeyedState
    end
  end
end
