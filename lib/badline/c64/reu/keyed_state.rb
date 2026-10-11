# frozen_string_literal: true

module Badline
  class C64
    class REU
      class DMA
        # The kinds of transfer, by name.
        TYPE_NAMES = %w[stash fetch swap verify].freeze

        # A transfer's fields in a keyed snapshot module, under `prefix`.
        # Before the first transfer, the fields it sets on starting are
        # absent.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}c64", @c64).int("#{prefix}expansion", @expansion).int("#{prefix}length", @length)
            out.int("#{prefix}events", @events)
            type = @type
            out.text("#{prefix}type", TYPE_NAMES.fetch(type)) unless type.nil?
            out.optional_int("#{prefix}c64_step", @c64_step).optional_int("#{prefix}expansion_step", @expansion_step)
            out.optional_int("#{prefix}last", @last).optional_int("#{prefix}ba_low_after_writes", @ba_low_after_writes)
            out.optional_int("#{prefix}swap_byte", @swap_byte).optional_int("#{prefix}held_read", @held_read)
            save_flag_fields(out, prefix)
          end

          def load_fields(input, prefix)
            @c64 = input.word("#{prefix}c64", @c64)
            @expansion = input.int("#{prefix}expansion", @expansion)
            @length = input.int("#{prefix}length", @length)
            @events = input.int("#{prefix}events", @events)
            type = input.choice("#{prefix}type", TYPE_NAMES + ["none"], "none")
            @type = type == "none" ? nil : TYPE_NAMES.index(type)
            @c64_step = input.optional_int("#{prefix}c64_step")
            @expansion_step = input.optional_int("#{prefix}expansion_step")
            @last = input.optional_int("#{prefix}last")
            @ba_low_after_writes = input.optional_int("#{prefix}ba_low_after_writes")
            @swap_byte = input.optional_int("#{prefix}swap_byte")
            @held_read = input.optional_int("#{prefix}held_read")
            load_flag_fields(input, prefix)
          end

          private

          def save_flag_fields(out, prefix)
            out.bool("#{prefix}holding", @holding).bool("#{prefix}waiting", @waiting)
            out.bool("#{prefix}stopped_after_write", @stopped_after_write)
            out.bool("#{prefix}swap_write_due", @swap_write_due).bool("#{prefix}swap_read_again", @swap_read_again)
            out.bool("#{prefix}moved_all", @moved_all).bool("#{prefix}extra_cycle", @extra_cycle)
          end

          def load_flag_fields(input, prefix)
            @holding = input.bool("#{prefix}holding", @holding)
            @waiting = input.bool("#{prefix}waiting", @waiting)
            @stopped_after_write = input.bool("#{prefix}stopped_after_write", @stopped_after_write)
            @swap_write_due = input.bool("#{prefix}swap_write_due", @swap_write_due)
            @swap_read_again = input.bool("#{prefix}swap_read_again", @swap_read_again)
            @moved_all = input.bool("#{prefix}moved_all", @moved_all)
            @extra_cycle = input.bool("#{prefix}extra_cycle", @extra_cycle)
          end
        end

        include KeyedState
      end

      class RAM
        # The data latch and each bank the REC has touched, as bank<N>; a
        # bank left out holds its power-on contents.
        module KeyedState
          def save_fields(out)
            out.int("latch", @latch)
            @banks.each_with_index { |bank, number| out.bytes("bank#{number}", bank) unless bank.empty? }
          end

          def load_fields(input)
            @latch = input.byte("latch", @latch)
            @banks.each_index do |number|
              @banks[number] = input.bytes("bank#{number}", "".b).bytes
            end
          end
        end

        include KeyedState
      end

      # The REU's fields in a keyed snapshot module (Snapshot::Keyed): the
      # REC's registers and the values its counters start from, an armed or
      # running transfer, the transfer under dma.*, and the RAM. The IRQ
      # line comes from the status register on load.
      module KeyedState
        def save_fields(out)
          out.int("status", @status).int("command", @command).int("c64", @c64).int("c64_start", @c64_start)
          out.int("expansion", @expansion).int("expansion_start", @expansion_start).int("bank", @bank)
          out.int("bank_start", @bank_start).int("length", @length).int("length_start", @length_start)
          out.int("interrupt_mask", @interrupt_mask).int("address_control", @address_control)
          out.bool("armed", @armed).bool("requested", @requested).bool("running", @running)
          out.bool("ba_was_low", @ba_was_low)
          @dma.save_fields(out, "dma.")
          @ram.save_fields(out)
          out
        end

        def load_fields(input)
          load_register_fields(input)
          @armed = input.bool("armed", @armed)
          @requested = input.bool("requested", @requested)
          @running = input.bool("running", @running)
          @ba_was_low = input.bool("ba_was_low", @ba_was_low)
          @dma.load_fields(input, "dma.")
          @ram.load_fields(input)
        end

        # Without calling back into the machine, which reads the line again.
        def restored!
          @irq = @status.anybits?(INTERRUPT_PENDING)
        end

        private

        def load_register_fields(input)
          @status = input.byte("status", @status)
          @command = input.byte("command", @command)
          @c64 = input.word("c64", @c64)
          @c64_start = input.word("c64_start", @c64_start)
          @expansion = input.word("expansion", @expansion)
          @expansion_start = input.word("expansion_start", @expansion_start)
          @bank = input.byte("bank", @bank)
          @bank_start = input.byte("bank_start", @bank_start)
          @length = input.word("length", @length)
          @length_start = input.word("length_start", @length_start)
          @interrupt_mask = input.byte("interrupt_mask", @interrupt_mask)
          @address_control = input.byte("address_control", @address_control)
        end
      end

      include KeyedState
    end
  end
end
