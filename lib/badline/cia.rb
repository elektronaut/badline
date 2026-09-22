# frozen_string_literal: true

require "forwardable"
require "badline/cia/interrupt_register"
require "badline/cia/serial"
require "badline/cia/timer"

module Badline
  # CIA (Complex Interface Adapter) chip
  class CIA
    include Addressable
    extend Forwardable

    attr_reader :start, :control_a, :control_b, :peripheral, :serial

    def_delegator :@icr, :status, :interrupt_status
    def_delegator :@icr, :mask,   :interrupt_control
    def_delegator :@icr, :assert!, :interrupt!
    def_delegator :@icr, :interrupted?

    def_delegator :@ta, :counter,  :timer_a
    def_delegator :@ta, :counter=, :timer_a=
    def_delegator :@ta, :latch,    :timer_a_latch
    def_delegator :@ta, :latch=,   :timer_a_latch=
    def_delegator :@tb, :counter,  :timer_b
    def_delegator :@tb, :counter=, :timer_b=
    def_delegator :@tb, :latch,    :timer_b_latch
    def_delegator :@tb, :latch=,   :timer_b_latch=

    def initialize(start: 0, peripheral: nil)
      addressable_at(start, length: 2**8)

      @peripheral = peripheral
      @data_port_a = 0xff
      @data_port_b = 0xff
      @data_dir_a = 0xff
      @data_dir_b = 0x0
      @port_b4_handler = nil
      @port_b4_high = true
      @cnt_high = true
      @cnt_rise = false
      @tod = TimeOfDay.new
      @icr = InterruptRegister.new
      @control_a = Status.new(%i[start output out_mode run_mode load
                                 in_mode serial_mode clock_frequency])
      @control_b = Status.new(%i[start output out_mode run_mode load
                                 in_cnt in_timer_a alarm])
      @ta = Timer.new(@control_a)
      @tb = Timer.new(@control_b)
      @serial = Serial.new(@control_a)
    end

    # Register a change handler on the PB4 line. On CIA 1, this feeds the
    # light pen input.
    def on_port_b4_change(&handler)
      @port_b4_handler = handler
    end

    # A falling edge on the FLAG pin. On CIA 1 the datasette's tape read
    # line drives it, on CIA 2 the serial bus SRQ.
    def flag! = raise_interrupt(:flag)

    def cycle!
      @icr.cycle!
      refresh_port_b4
      sample_cnt
      update_timers
      @serial.cycle!(@ta.underflowed) { trigger_serial }
      @tod.cycle! { trigger_alarm }
    end

    def read_port_a
      lines = driven_lines(@data_port_a, @data_dir_a)
      return lines unless peripheral

      lines & peripheral.read_a(lines, driven_lines(@data_port_b, @data_dir_b))
    end

    # Port A as driven by the data/direction registers alone, without
    # peripheral pulldown. Cheap path for the VIC bank lookup.
    def port_a_lines
      driven_lines(@data_port_a, @data_dir_a)
    end

    def read_port_b
      lines = driven_lines(@data_port_b, @data_dir_b)
      lines &= peripheral.read_b(driven_lines(@data_port_a, @data_dir_a), lines) if peripheral
      apply_timer_output(lines)
    end

    def peek(addr)
      case index(addr) & 0x0f
      when 0x00 then read_port_a
      when 0x01 then read_port_b
      when 0x02 then @data_dir_a
      when 0x03 then @data_dir_b
      when 0x04 then low_byte(@ta.counter)
      when 0x05 then high_byte(@ta.counter)
      when 0x06 then low_byte(@tb.counter)
      when 0x07 then high_byte(@tb.counter)
      when 0x08 then @tod.tenths
      when 0x09 then @tod.seconds
      when 0x0a then @tod.minutes
      when 0x0b then @tod.hours
      when 0x0c then @serial.data
      when 0x0d then @icr.read
      when 0x0e then control_a.value
      when 0x0f then control_b.value
      end
    end

    def poke(addr, value)
      case index(addr) & 0x0f
      when 0x00 then @data_port_a = value
      when 0x01 then update_port_b { @data_port_b = value }
      when 0x02 then @data_dir_a = value
      when 0x03 then update_port_b { @data_dir_b = value }
      when 0x04 then @ta.write_latch_low(value)
      when 0x05 then @ta.write_latch_high(value)
      when 0x06 then @tb.write_latch_low(value)
      when 0x07 then @tb.write_latch_high(value)
      when 0x08 then @tod.write(:tenths, value, alarm: control_b.alarm?)
      when 0x09 then @tod.write(:seconds, value, alarm: control_b.alarm?)
      when 0x0a then @tod.write(:minutes, value, alarm: control_b.alarm?)
      when 0x0b then @tod.write_hours(value, alarm: control_b.alarm?)
      when 0x0c then @serial.write(value)
      when 0x0d then @icr.write(value)
      when 0x0e then write_control_a(value)
      when 0x0f then @tb.write_control(value)
      end
    end

    private

    def update_port_b
      yield
      refresh_port_b4
    end

    # PB4 is also control port 1's fire line, and a peripheral pulls it low
    # without any register write, so the level is resampled every cycle rather
    # than only after a poke.
    def refresh_port_b4
      return unless @port_b4_handler

      high = driven_lines(@data_port_b, @data_dir_b).anybits?(0x10) &&
             (peripheral.nil? || peripheral.port_b4_high?)
      return if high == @port_b4_high

      @port_b4_high = high
      @port_b4_handler.call(high)
    end

    def driven_lines(register, direction)
      # Output bits are driven from the data register; input bits float high.
      # External peripherals can still pull any line low (wired-AND).
      (register & direction) | (~direction & 0xff)
    end

    def apply_timer_output(value)
      value = with_bit(value, 6, @ta.output?) if control_a.output?
      value = with_bit(value, 7, @tb.output?) if control_b.output?
      value
    end

    def with_bit(value, bit, set)
      set ? value | (1 << bit) : value & ~(1 << bit)
    end

    def trigger_alarm = raise_interrupt(:alarm)
    def trigger_serial = raise_interrupt(:serial)

    def raise_interrupt(source) = @icr.flag(source)

    # CNT is sampled once a cycle. When the serial port drives it from this
    # cycle's timer A underflow, the new level is picked up on the next one.
    def sample_cnt
      level = @serial.cnt
      return @cnt_rise = false if level == @cnt_high

      @cnt_high = level
      @cnt_rise = level
      @serial.rising_edge! { trigger_serial } if level
    end

    def update_timers
      @ta.cycle!(@control_a.value.nobits?(0x20) || @cnt_rise)
      cycle_timer_b
      if @ta.underflowed
        interrupt_status.timer_a = true
        interrupt! if interrupt_control.timer_a?
      end
      return unless @tb.underflowed

      @icr.timer_b_underflow!
    end

    # CRB bits 6-5 pick timer B's source: ø2, CNT edges, timer A
    # underflows, or timer A underflows gated by the CNT level. Every source
    # drives the same count-enable line, so a cascaded underflow goes through
    # the input pipeline exactly as a CNT edge does.
    def cycle_timer_b
      case @control_b.value & 0x60
      when 0x00 then @tb.cycle!(true)
      when 0x20 then @tb.cycle!(@cnt_rise)
      when 0x40 then @tb.cycle!(@ta.underflowed)
      else           @tb.cycle!(@ta.underflowed && @cnt_high)
      end
    end

    def write_control_a(value)
      was_output = control_a.serial_mode?
      @ta.write_control(value)
      @serial.reset! { trigger_serial } if control_a.serial_mode? != was_output
      @tod.fifty_hz = control_a.clock_frequency?
    end
  end
end
