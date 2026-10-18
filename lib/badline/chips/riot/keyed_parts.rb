# frozen_string_literal: true

module Badline
  module Chips
    class RIOT
      class Timer
        # The timer's fields in a keyed snapshot module, under `prefix`, the
        # divider by its A1-A0 code.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}counter", @counter).int("#{prefix}interval", DIVIDERS.index(@divider))
            out.int("#{prefix}prescale", @prescale)
            out.bool("#{prefix}expired", @expired).bool("#{prefix}flag", @flag)
            out.bool("#{prefix}irq_enabled", @irq_enabled).bool("#{prefix}fired", @fired)
          end

          def load_fields(input, prefix)
            @counter = input.byte("#{prefix}counter", @counter)
            @divider = DIVIDERS[input.masked("#{prefix}interval", DIVIDERS.index(@divider), 0x03)]
            @prescale = input.int("#{prefix}prescale", @prescale).clamp(1, @divider)
            @expired = input.bool("#{prefix}expired", @expired)
            @flag = input.bool("#{prefix}flag", @flag)
            @irq_enabled = input.bool("#{prefix}irq_enabled", @irq_enabled)
            @fired = input.bool("#{prefix}fired", @fired)
          end
        end

        include KeyedState
      end

      # The RIOT's fields in a keyed snapshot module (Snapshot::Keyed): the
      # RAM, the port and direction registers, the edge detector and the
      # level on PA7, and the timer under timer. The peripheral restores its
      # own state.
      module KeyedState
        def save_fields(out)
          out.bytes("ram", @ram)
          out.int("ora", @ora).int("orb", @orb).int("ddra", @ddra).int("ddrb", @ddrb)
          out.bool("pa7_high", @pa7_high).bool("pa7_active", @pa7_active).bool("pa7_flag", @pa7_flag)
          out.bool("edge_irq_enabled", @edge_irq_enabled).bool("rising_edge", @rising_edge)
          @timer.save_fields(out, "timer.")
          out
        end

        def load_fields(input)
          input.bytes_into("ram", @ram)
          @ora = input.byte("ora", @ora)
          @orb = input.byte("orb", @orb)
          @ddra = input.byte("ddra", @ddra)
          @ddrb = input.byte("ddrb", @ddrb)
          load_edge_fields(input)
          @timer.load_fields(input, "timer.")
        end

        private

        def load_edge_fields(input)
          @pa7_high = input.bool("pa7_high", @pa7_high)
          @pa7_active = input.bool("pa7_active", @pa7_active)
          @pa7_flag = input.bool("pa7_flag", @pa7_flag)
          @edge_irq_enabled = input.bool("edge_irq_enabled", @edge_irq_enabled)
          @rising_edge = input.bool("rising_edge", @rising_edge)
        end
      end

      include KeyedState
    end
  end
end
