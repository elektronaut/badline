# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # CIA1 and CIA2 2.3: the registers, both timers' counters and
      # latches, the interrupt flags and mask, the TOD clock, its alarm and
      # latch, and the shift register.
      #
      # Each timer's VICE state word carries its start, one-shot and input
      # bits and whether its count pipeline is full, which is what badline's
      # pipeline holds between loads. A load or one-shot stop in flight,
      # the TOD divider's phase within a tenth and the shift register's
      # progress through a byte are approximations both ways.
      module CIAs
        MAJOR = 2
        MINOR = 3
        NAMES = %w[CIA1 CIA2].freeze
        PORTS = %i[@data_port_a @data_port_b @data_dir_a @data_dir_b].freeze
        TOD_FIELDS = %i[tenths seconds minutes hours].freeze

        # VICE's timer state bits.
        START = 0x001
        COUNT2 = 0x002
        ONESHOT = 0x008
        PHI2IN = 0x020
        COUNT3 = 0x040
        COUNT = 0x800

        module_function

        def export(computer)
          [computer.cia1, computer.cia2].each_with_index.map do |cia, i|
            fields = FieldWriter.new
            registers(cia, fields)
            time_of_day(cia.time_of_day, fields)
            internals(cia, fields)
            fields.section(NAMES[i], MAJOR, MINOR)
          end
        end

        def registers(cia, fields)
          PORTS.each { |port| fields.byte(cia.instance_variable_get(port)) }
          fields.word(cia.timer_a).word(cia.timer_b)
          cia.time_of_day.registers.first(4).each { |value| fields.byte(value) }
          fields.byte(cia.serial.data).byte(cia.interrupt_control.value)
          fields.byte(cia.control_a.value).byte(cia.control_b.value)
          fields.word(cia.timer_a_latch).word(cia.timer_b_latch).byte(cia.interrupt_status.value)
          ta, tb = timers(cia)
          fields.byte((toggle?(ta) ? 0x40 : 0) | (toggle?(tb) ? 0x80 : 0) |
                      (ta.underflowed ? 0x04 : 0) | (tb.underflowed ? 0x08 : 0))
          fields.byte(cia.serial.instance_variable_get(:@steps).clamp(0, 0xff))
        end

        def time_of_day(tod, fields)
          registers = tod.registers
          registers[4, 4].each { |value| fields.byte(value) }
          fields.byte(0) # cycles since the ICR was read
          fields.byte(registers[9] | (registers[8] << 1)) # latched, stopped
          latch = tod.instance_variable_get(:@latch) || tod.instance_variable_get(:@clock)
          TOD_FIELDS.each { |field| fields.byte(latch[field]) }
          fields.qword(tod_ticks(tod))
        end

        # The cycles until the TOD clock next steps a tenth.
        def tod_ticks(tod)
          per_pulse = tod.instance_variable_get(:@cycles_per_pulse)
          mains = tod.instance_variable_get(:@mains_hz)
          to_pulse = (per_pulse - tod.instance_variable_get(:@accumulator) + mains - 1) / mains
          pulses = tod.instance_variable_get(:@match) - tod.instance_variable_get(:@pulses)
          to_pulse + ([pulses, 0].max * per_pulse / mains)
        end

        def internals(cia, fields)
          timers(cia).each { |timer| fields.word(timer_state(timer)) }
          serial = cia.serial
          shift = serial.instance_variable_get(:@shift)
          fields.byte(shift & 0xff).flag(!serial.instance_variable_get(:@pending).nil?).flag(cia.interrupted?)
          fields.byte(cia.time_of_day.instance_variable_get(:@pulses))
          fields.byte(shift >> 8).byte(0)
          fields.byte((serial.sp_in ? 0x80 : 0) | (serial.cnt_in ? 0x40 : 0))
        end

        def timers(cia) = [cia.instance_variable_get(:@ta), cia.instance_variable_get(:@tb)]

        def toggle?(timer) = timer.instance_variable_get(:@toggle)

        def timer_state(timer)
          control = timer.control.value
          pipe = timer.instance_variable_get(:@pipe)
          (control & (START | ONESHOT)) | (control.nobits?(0x60) ? PHI2IN : 0) |
            (pipe.anybits?(0b10) ? COUNT2 : 0) | (pipe.anybits?(0b01) ? COUNT3 | COUNT : 0)
        end

        def import(section, computer)
          cia = section.name == NAMES.first ? computer.cia1 : computer.cia2
          Import.new(FieldReader.new(section)).apply(cia)
        end
      end
    end
  end
end
