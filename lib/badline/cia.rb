# frozen_string_literal: true

require "badline/cia/interrupt_register"
require "badline/cia/serial"
require "badline/cia/timer"

module Badline
  # CIA (Complex Interface Adapter) chip
  class CIA
    include Addressable

    attr_reader :start, :control_a, :control_b, :peripheral, :serial

    def interrupt_status = @icr.status

    def interrupt_control = @icr.mask

    def interrupt!(delay = 1) = @icr.assert!(delay)

    def timer_a = @ta.counter

    def timer_a=(value)
      @ta.counter = value
    end

    def timer_a_latch = @ta.latch

    def timer_a_latch=(value)
      @ta.latch = value
    end

    def timer_b = @tb.counter

    def timer_b=(value)
      @tb.counter = value
    end

    def timer_b_latch = @tb.latch

    def timer_b_latch=(value)
      @tb.latch = value
    end

    def initialize(start: 0, peripheral: nil)
      addressable_at(start, length: 2**8)

      @peripheral = peripheral
      @port_b4_handler = nil
      @port_b4_high = true
      reset!
    end

    # The RES line: ports back to inputs, timers stopped with their latches
    # full, interrupts masked and the TOD clock stopped at 1:00:00.0. The
    # PB4 level carries over and is resampled on the next cycle.
    def reset!
      @data_port_a = 0x00
      @data_port_b = 0x00
      @data_dir_a = 0x00
      @data_dir_b = 0x00
      @port_b4_driven_high = true
      @cnt_high = true
      @cnt_rise = false
      @tod = TimeOfDay.new
      @icr = InterruptRegister.new
      @icr_status = @icr.status
      @control_a = ControlRegister.new(%i[start output out_mode run_mode load
                                          in_mode serial_mode clock_frequency])
      @control_b = ControlRegister.new(%i[start output out_mode run_mode load
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

    def interrupted? = @icr_status.value >= 0x80

    def cycle!
      @icr.cycle! unless @icr.quiet
      refresh_port_b4 if @port_b4_handler
      level = @serial.cnt
      level == @cnt_high ? @cnt_rise = false : cnt_edge(level)
      underflowed = update_timers
      @serial.cycle!(underflowed) { trigger_serial } if underflowed || !@serial.idle
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
      @port_b4_driven_high = driven_lines(@data_port_b, @data_dir_b).anybits?(0x10)
      refresh_port_b4 if @port_b4_handler
    end

    # PB4 is also control port 1's fire line, and a peripheral pulls it low
    # without any register write, so the level is resampled every cycle rather
    # than only after a poke.
    def refresh_port_b4
      high = @port_b4_driven_high && (peripheral.nil? || peripheral.port_b4_high?)
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
    def cnt_edge(level)
      @cnt_high = level
      @cnt_rise = level
      @serial.rising_edge! { trigger_serial } if level
    end

    # Returns whether timer A underflowed, which clocks the serial port.
    #
    # CRB bits 6-5 pick timer B's source: ø2, CNT edges, timer A
    # underflows, or timer A underflows gated by the CNT level. Every source
    # drives the same count-enable line, so a cascaded underflow goes through
    # the input pipeline exactly as a CNT edge does.
    def update_timers
      @ta.cycle!(@control_a.value & 0x20 == 0x20 ? @cnt_rise : true)
      underflowed = @ta.underflowed
      @tb.cycle!(
        case @control_b.value & 0x60
        when 0x00 then true
        when 0x20 then @cnt_rise
        when 0x40 then underflowed
        else underflowed && @cnt_high
        end
      )
      if underflowed
        interrupt_status.timer_a = true
        interrupt! if interrupt_control.timer_a?
      end
      @icr.timer_b_underflow! if @tb.underflowed
      underflowed
    end

    def write_control_a(value)
      was_output = control_a.serial_mode?
      @ta.write_control(value)
      @serial.reset! { trigger_serial } if control_a.serial_mode? != was_output
      @tod.fifty_hz = control_a.clock_frequency?
    end
  end
end
