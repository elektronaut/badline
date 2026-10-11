# frozen_string_literal: true

module Badline
  module Chips
    class CIA
      class Timer
        # A timer's fields in a keyed snapshot module (Snapshot::Keyed),
        # under `prefix`: the counter, the latch and the pipeline between
        # them. The fast-path flags are worked out again on load.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}counter", @counter).int("#{prefix}latch", @latch).int("#{prefix}pipe", @pipe)
            out.int("#{prefix}load_delay", @load_delay).bool("#{prefix}reload", @reload)
            out.bool("#{prefix}underflowed", @underflowed).int("#{prefix}oneshot_linger", @oneshot_linger)
            out.bool("#{prefix}toggle", @toggle)
          end

          def load_fields(input, prefix)
            @counter = input.word("#{prefix}counter", @counter)
            @latch = input.word("#{prefix}latch", @latch)
            @pipe = input.masked("#{prefix}pipe", @pipe, 0b11)
            @load_delay = input.int("#{prefix}load_delay", @load_delay)
            @reload = input.bool("#{prefix}reload", @reload)
            @underflowed = input.bool("#{prefix}underflowed", @underflowed)
            @oneshot_linger = input.int("#{prefix}oneshot_linger", @oneshot_linger)
            @toggle = input.bool("#{prefix}toggle", @toggle)
          end

          def restored! = settle
        end

        include KeyedState
      end

      class InterruptRegister
        # The interrupt register's fields in a keyed snapshot module, under
        # `prefix`: the mask, the flags, an assert on its way and the reads
        # whose acknowledge is still landing.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}mask", @mask.value).int("#{prefix}status", @status.value)
            out.int("#{prefix}pending", @pending)
            out.optional_int("#{prefix}read", @read).optional_int("#{prefix}read_last_cycle", @read_last_cycle)
            out.optional_int("#{prefix}read_two_cycles_ago", @read_two_cycles_ago)
            out.bool("#{prefix}timer_b_bug", @timer_b_bug)
          end

          def load_fields(input, prefix)
            @mask.value = input.byte("#{prefix}mask", @mask.value)
            @status.value = input.byte("#{prefix}status", @status.value)
            @pending = input.int("#{prefix}pending", @pending)
            @read = input.optional_int("#{prefix}read")
            @read_last_cycle = input.optional_int("#{prefix}read_last_cycle")
            @read_two_cycles_ago = input.optional_int("#{prefix}read_two_cycles_ago")
            @timer_b_bug = input.bool("#{prefix}timer_b_bug", @timer_b_bug)
          end

          # Quiet when nothing is due and no read is recent enough to matter.
          def restored!
            @quiet = @pending.zero? && @read.nil? && @read_last_cycle.nil? && @read_two_cycles_ago.nil?
          end
        end

        include KeyedState
      end

      class Serial
        # The serial port's fields in a keyed snapshot module, under
        # `prefix`: the registers, the bit count, the delay lines, the CNT
        # and SP levels, and whether the next cycle can be skipped, which
        # can lag what the delay lines show by a cycle.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}data", @data).int("#{prefix}shift", @shift).int("#{prefix}steps", @steps)
            out.optional_int("#{prefix}empty_in", @empty_in).optional_int("#{prefix}busy_in", @busy_in)
            out.bool("#{prefix}busy", @busy).bool("#{prefix}abandoned", @abandoned)
            out.optional_int("#{prefix}pending", @pending).bool("#{prefix}underflow_high", @underflow_high)
            out.bool("#{prefix}in_flight", @in_flight).int("#{prefix}flight_up", @flight_up)
            out.int("#{prefix}flight_down", @flight_down).bool("#{prefix}cnt", @cnt).bool("#{prefix}cnt_in", @cnt_in)
            out.bool("#{prefix}sp_in", @sp_in).bool("#{prefix}sp_out", @sp_out).bool("#{prefix}idle", @idle)
          end

          def load_fields(input, prefix)
            @data = input.byte("#{prefix}data", @data)
            @shift = input.byte("#{prefix}shift", @shift)
            @steps = input.int("#{prefix}steps", @steps)
            @empty_in = input.optional_int("#{prefix}empty_in")
            @busy_in = input.optional_int("#{prefix}busy_in")
            @busy = input.bool("#{prefix}busy", @busy)
            @abandoned = input.bool("#{prefix}abandoned", @abandoned)
            @pending = input.optional_int("#{prefix}pending")
            load_line_fields(input, prefix)
          end

          def restored! = nil

          private

          def load_line_fields(input, prefix)
            @underflow_high = input.bool("#{prefix}underflow_high", @underflow_high)
            @in_flight = input.bool("#{prefix}in_flight", @in_flight)
            @flight_up = input.int("#{prefix}flight_up", @flight_up)
            @flight_down = input.int("#{prefix}flight_down", @flight_down)
            @cnt = input.bool("#{prefix}cnt", @cnt)
            @cnt_in = input.bool("#{prefix}cnt_in", @cnt_in)
            @sp_in = input.bool("#{prefix}sp_in", @sp_in)
            @sp_out = input.bool("#{prefix}sp_out", @sp_out)
            @idle = input.bool("#{prefix}idle", @idle)
          end
        end

        include KeyedState
      end

      class TimeOfDay
        # The TOD clock's fields in a keyed snapshot module, under `prefix`:
        # the clock, the alarm and a latched read field by field, the
        # pulses towards the next tenth, and the mains divider's phase in
        # cycle·Hz (it reaches the clock rate when a pulse arrives). The
        # 50/60 Hz divider comes from CRA bit 7 on load.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}mains_phase", @accumulator).int("#{prefix}pulses", @pulses)
            out.bool("#{prefix}stopped", @stopped).bool("#{prefix}alarm_pending", @alarm_pending)
            FIELDS.each do |field|
              out.int("#{prefix}clock.#{field}", @clock[field]).int("#{prefix}alarm.#{field}", @alarm[field])
            end
            latch = @latch
            FIELDS.each { |field| out.int("#{prefix}latch.#{field}", latch[field]) } if latch
          end

          def load_fields(input, prefix)
            @accumulator = input.int("#{prefix}mains_phase", @accumulator)
            @pulses = input.int("#{prefix}pulses", @pulses)
            @stopped = input.bool("#{prefix}stopped", @stopped)
            @alarm_pending = input.bool("#{prefix}alarm_pending", @alarm_pending)
            FIELDS.each do |field|
              @clock[field] = input.byte("#{prefix}clock.#{field}", @clock[field])
              @alarm[field] = input.byte("#{prefix}alarm.#{field}", @alarm[field])
            end
            load_latch_fields(input, prefix)
          end

          def restored!(fifty_hz)
            self.fifty_hz = fifty_hz
          end

          private

          def load_latch_fields(input, prefix)
            return @latch = nil if input.optional_int("#{prefix}latch.hours").nil?

            @latch = FIELDS.to_h { |field| [field, input.byte("#{prefix}latch.#{field}", 0)] }
          end
        end

        include KeyedState
      end

      # The CIA's fields in a keyed snapshot module (Snapshot::Keyed): the
      # ports, the control registers, the PB4 and CNT levels, and its parts
      # under ta., tb., icr., sdr. and tod.
      module KeyedState
        def save_fields(out)
          out.int("pra", @data_port_a).int("prb", @data_port_b).int("ddra", @data_dir_a).int("ddrb", @data_dir_b)
          out.int("cra", @control_a.value).int("crb", @control_b.value)
          out.bool("pb4_high", @port_b4_high).bool("pb4_driven_high", @port_b4_driven_high)
          out.bool("cnt_high", @cnt_high).bool("cnt_rise", @cnt_rise)
          @ta.save_fields(out, "ta.")
          @tb.save_fields(out, "tb.")
          @icr.save_fields(out, "icr.")
          @serial.save_fields(out, "sdr.")
          @tod.save_fields(out, "tod.")
          out
        end

        def load_fields(input)
          @data_port_a = input.byte("pra", @data_port_a)
          @data_port_b = input.byte("prb", @data_port_b)
          @data_dir_a = input.byte("ddra", @data_dir_a)
          @data_dir_b = input.byte("ddrb", @data_dir_b)
          @control_a.value = input.byte("cra", @control_a.value)
          @control_b.value = input.byte("crb", @control_b.value)
          @port_b4_high = input.bool("pb4_high", @port_b4_high)
          @port_b4_driven_high = input.bool("pb4_driven_high", @port_b4_driven_high)
          @cnt_high = input.bool("cnt_high", @cnt_high)
          @cnt_rise = input.bool("cnt_rise", @cnt_rise)
          load_part_fields(input)
        end

        def restored!
          @ta.restored!
          @tb.restored!
          @icr.restored!
          @serial.restored!
          @tod.restored!(@control_a.clock_frequency?)
        end

        private

        def load_part_fields(input)
          @ta.load_fields(input, "ta.")
          @tb.load_fields(input, "tb.")
          @icr.load_fields(input, "icr.")
          @serial.load_fields(input, "sdr.")
          @tod.load_fields(input, "tod.")
        end
      end

      include KeyedState
    end
  end
end
