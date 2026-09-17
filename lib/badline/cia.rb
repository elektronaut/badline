# frozen_string_literal: true

require "forwardable"
require "badline/cia/timer"

module Badline
  # CIA (Complex Interface Adapter) chip
  class CIA
    include Addressable
    extend Forwardable

    attr_reader :start, :control_a, :control_b, :interrupt_status, :interrupt_control, :peripheral

    def_delegator :@ta, :counter, :timer_a
    def_delegator :@ta, :latch,   :timer_a_latch
    def_delegator :@tb, :counter, :timer_b
    def_delegator :@tb, :latch,   :timer_b_latch

    # Written out rather than delegated: Forwardable's setter delegation
    # is one of the constructs the Spinel AOT compiler can't rewrite.
    def timer_a=(value)
      @ta.counter = value
    end

    def timer_a_latch=(value)
      @ta.latch = value
    end

    def timer_b=(value)
      @tb.counter = value
    end

    def timer_b_latch=(value)
      @tb.latch = value
    end

    def initialize(start: 0, peripheral: nil)
      addressable_at(start, length: 2**8)

      @peripheral = peripheral
      @data_port_a = 0xff
      @data_port_b = 0xff
      @data_dir_a = 0xff
      @data_dir_b = 0x0
      @irq_pending = 0
      @serial_data = 0x0
      @tod = TimeOfDay.new
      @interrupt_control = Status.new([:timer_a, :timer_b, :alarm, :serial,
                                       :flag, 0, 0, 0])
      @interrupt_status = Status.new([:timer_a, :timer_b, :alarm, :serial,
                                      :flag, 0, 0, :interrupt])
      @control_a = Status.new(%i[start output out_mode run_mode load
                                 in_mode serial_mode clock_frequency])
      @control_b = Status.new(%i[start output out_mode run_mode load
                                 in_cnt in_timer_a alarm])
      @ta = Timer.new(@control_a)
      @tb = Timer.new(@control_b)
    end

    def interrupt!(delay = 1)
      @irq_pending = @irq_pending.positive? ? [@irq_pending, delay].min : delay
    end

    def interrupted?
      interrupt_status.value.anybits?(0x80)
    end

    def cycle!
      if @irq_pending.positive?
        @irq_pending -= 1
        interrupt_status.interrupt = true if @irq_pending.zero?
      end
      update_timers
      @tod.cycle! { trigger_alarm }
    end

    def read_port_a
      pulldown = peripheral ? peripheral.read_a(@data_port_a, @data_port_b) : 0xff
      driven_lines(@data_port_a, @data_dir_a) & pulldown
    end

    # Port A as driven by the data/direction registers alone, without
    # peripheral pulldown. Cheap path for the VIC bank lookup.
    def port_a_lines
      driven_lines(@data_port_a, @data_dir_a)
    end

    def read_port_b
      pulldown = peripheral ? peripheral.read_b(@data_port_a, @data_port_b) : 0xff
      value = driven_lines(@data_port_b, @data_dir_b) & pulldown
      apply_timer_output(value)
    end

    def peek(addr)
      case offset_of(addr) & 0x0f
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
      when 0x0c then @serial_data
      when 0x0d
        value = interrupt_status.value
        interrupt_status.value = 0x0 # Burn after reading
        @irq_pending = 0
        value
      when 0x0e then control_a.value
      when 0x0f then control_b.value
      end
    end

    def poke(addr, value)
      case offset_of(addr) & 0x0f
      when 0x00 then @data_port_a = value
      when 0x01 then @data_port_b = value
      when 0x02 then @data_dir_a = value
      when 0x03 then @data_dir_b = value
      when 0x04 then @ta.write_latch_low(value)
      when 0x05 then @ta.write_latch_high(value)
      when 0x06 then @tb.write_latch_low(value)
      when 0x07 then @tb.write_latch_high(value)
      when 0x08 then @tod.write(:tenths, value, alarm: control_b.alarm?)
      when 0x09 then @tod.write(:seconds, value, alarm: control_b.alarm?)
      when 0x0a then @tod.write(:minutes, value, alarm: control_b.alarm?)
      when 0x0b then @tod.write_hours(value, alarm: control_b.alarm?)
      when 0x0c
        # TODO: Serial
      when 0x0d then write_interrupt_control(value)
      when 0x0e then @ta.write_control(value)
      when 0x0f then @tb.write_control(value)
      end
    end

    private

    def driven_lines(register, direction)
      # Output bits are driven from the data register; input bits float high.
      # External peripherals can still pull any line low (wired-AND).
      (register & direction) | (~direction & 0xff)
    end

    def apply_timer_output(value)
      value = with_bit(value, 6, timer_a_output?) if control_a.output?
      value = with_bit(value, 7, timer_b_output?) if control_b.output?
      value
    end

    def timer_a_output?
      control_a.out_mode? ? @ta.toggle? : @ta.underflowed
    end

    def timer_b_output?
      control_b.out_mode? ? @tb.toggle? : @tb.underflowed
    end

    def with_bit(value, bit, set)
      set ? value | (1 << bit) : value & ~(1 << bit)
    end

    def trigger_alarm
      interrupt_status.alarm = true
      interrupt! if interrupt_control.alarm?
    end

    def update_timers
      @ta.cycle!(@control_a.value.nobits?(0x20), true)
      crb = @control_b.value
      if crb.anybits?(0x40)
        @tb.cycle!(true, @ta.underflowed)
      else
        @tb.cycle!(crb.nobits?(0x20), true)
      end
      if @ta.underflowed
        interrupt_status.timer_a = true
        interrupt! if interrupt_control.timer_a?
      end
      return unless @tb.underflowed

      interrupt_status.timer_b = true
      interrupt! if interrupt_control.timer_b?
    end

    def write_interrupt_control(value)
      # Bit 7 selects clear (0) or set (1) for the interrupts in bits 0-4.
      interrupt_control.value = if value.nobits?(0x80)
                                  interrupt_control.value & ~(value & 0x1f)
                                else
                                  interrupt_control.value | (value & 0x1f)
                                end
      return unless interrupt_control.value.anybits?(interrupt_status.value & 0x1f)

      interrupt!(2) unless interrupted?
    end
  end
end
