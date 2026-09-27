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
            cia.serial.instance_variable_set(:@data, @sdr)
            cia.serial.instance_variable_set(:@shift, @shift)
            load_timers(cia)
            load_time_of_day(cia.time_of_day)
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
            timers = CIAs.timers(cia)
            [@control_a, @control_b].zip(timers).each_with_index do |(control, timer), i|
              timer.control.value = control & ~0x10
              timer.instance_variable_set(:@toggle, @toggles.anybits?(0x40 << i))
              state = @states[i]
              pipe = (state.anybits?(COUNT2) ? 0b10 : 0) | (state.anybits?(COUNT3) ? 0b01 : 0)
              timer.instance_variable_set(:@pipe, pipe)
              timer.send(:settle)
            end
          end

          def load_time_of_day(tod)
            tod.instance_variable_set(:@clock, TOD_FIELDS.zip(@clock).to_h)
            tod.instance_variable_set(:@alarm, TOD_FIELDS.zip(@alarm).to_h)
            tod.instance_variable_set(:@latch, @latch && TOD_FIELDS.zip(@latch).to_h)
            tod.instance_variable_set(:@stopped, @stopped)
            tod.instance_variable_set(:@pulses, @pulses)
            tod.fifty_hz = @control_a.anybits?(0x80)
            tod.instance_variable_set(:@accumulator, accumulator(tod))
          end

          # Where the TOD divider stands, from the cycles left to the next
          # tenth: those past the pulses still to come before it are the
          # cycles to the next pulse.
          def accumulator(tod)
            per_pulse = tod.instance_variable_get(:@cycles_per_pulse)
            mains = tod.instance_variable_get(:@mains_hz)
            pulses = [tod.instance_variable_get(:@match) - @pulses, 0].max
            to_pulse = @ticks - (pulses * per_pulse / mains)
            (per_pulse - (to_pulse * mains)).clamp(0, per_pulse - 1)
          end
        end
      end
    end
  end
end
