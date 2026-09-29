# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CIAs
        # Reads a CIA module and puts it into one of badline's CIAs.
        class Import
          def initialize(fields)
            @fields = fields
            f = fields
            @ports = f.bytes(4)
            @counters = [f.word, f.word]
            @clock = f.bytes(4)
            @sdr, @mask, @control_a, @control_b = f.bytes(4)
            @latches = [f.word, f.word]
            @status, @toggles = f.bytes(2)
            read_time_of_day
            read_internals
          end

          def apply(cia)
            @ports.each_with_index { |value, port| cia.poke(cia.start + port, value) }
            cia.timer_a, cia.timer_b = @counters
            cia.timer_a_latch, cia.timer_b_latch = @latches
            cia.interrupt_control.value = @mask & 0x1f
            cia.interrupt_status.value = @status
            cia.serial.restore_shift(@sdr, @shift)
            load_timers(cia)
            cia.time_of_day.fifty_hz = @control_a.anybits?(0x80)
            cia.time_of_day.restore_fields(@clock, @alarm, @latch)
            cia.time_of_day.restore_divider(@stopped, @pulses, @ticks)
          end

          private

          def read_time_of_day
            f = @fields
            f.skip(1) # the shift register's half-bits
            @alarm = f.bytes(4)
            f.skip(1) # cycles since the ICR was read
            state = f.byte
            @stopped = state.anybits?(2)
            latch = f.bytes(4)
            @latch = state.anybits?(1) ? latch : nil
            @ticks = f.qword
          end

          def read_internals
            f = @fields
            @states = [f.word, f.word]
            @shift = f.byte
            f.skip(2) # whether the SDR holds a byte to send, the IRQ line
            @pulses = f.byte.clamp(0, 5)
          end

          # Each timer takes its control register without the load strobe,
          # its output toggle, and whether its count pipeline is full.
          def load_timers(cia)
            [@control_a, @control_b].zip(cia.timers).each_with_index do |(control, timer), i|
              state = @states[i]
              pipe = (state.anybits?(COUNT2) ? 0b10 : 0) | (state.anybits?(COUNT3) ? 0b01 : 0)
              timer.restore_pipeline(control, @toggles.anybits?(0x40 << i), pipe)
            end
          end
        end
      end
    end
  end
end
