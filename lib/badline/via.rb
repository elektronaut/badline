# frozen_string_literal: true

require "badline/via/control_lines"
require "badline/via/fast_forward"
require "badline/via/interrupt_register"
require "badline/via/shift_register"
require "badline/via/timer1"
require "badline/via/timer2"

module Badline
  # VIA (Versatile Interface Adapter): the MOS 6522, two ports with
  # handshake lines, two timers and a shift register. The 1541 has two.
  #
  # Sixteen registers repeat across a 1 KB window. The control pins take
  # levels from outside through ca1= and friends, and PB6 takes its pulses
  # for timer 2 through pb6= alone: the peripheral's port B input doesn't
  # feed the counter.
  class VIA
    include Addressable
    include FastForward

    attr_reader :start, :peripheral, :shift_register, :acr, :pcr

    def timer1 = @t1.counter

    def timer1_latch = @t1.latch

    def timer2 = @t2.counter

    def interrupt_flags = @ifr.read

    def interrupt_enable = @ifr.read_enable

    def initialize(start: 0, peripheral: nil)
      addressable_at(start, length: 2**10)

      @peripheral = peripheral
      @t1 = Timer1.new
      @t2 = Timer2.new
      @shift_register = ShiftRegister.new
      @ifr = InterruptRegister.new
      @ca = ControlLines.new(@ifr, c1_flag: InterruptRegister::CA1, c2_flag: InterruptRegister::CA2,
                                   handshake_on_read: true)
      @cb = ControlLines.new(@ifr, c1_flag: InterruptRegister::CB1, c2_flag: InterruptRegister::CB2,
                                   handshake_on_read: false)
      @pb6_high = true
      @acr = 0x00
      reset!
    end

    # The RES line clears every register but the timers and the shift
    # register, which carry on counting, and so releases IRQ.
    def reset!
      @ora = @orb = @ddra = @ddrb = 0x00
      @latch_a = @latch_b = 0xff
      @ifr.reset!
      @ca.reset!
      @cb.reset!
      write_acr(0x00)
      @pcr = 0x00
    end

    def irq? = @ifr.irq?

    def cycle!
      @ca.cycle! if @ca.pulsing?
      @cb.cycle! if @cb.pulsing?
      @ifr.set(InterruptRegister::TIMER1) if @t1.cycle!(@acr.anybits?(0x40))
      @ifr.set(InterruptRegister::TIMER2) if @t2.cycle!(@sr_uses_t2)
      @ifr.set(InterruptRegister::SR) if @shift_register.cycle!(@t2.low_underflowed)
    end

    # Port A as driven by ORA and DDRA, input lines floating high.
    def port_a_output = driven_lines(@ora, @ddra)

    # Port B as driven by ORB and DDRB, with PB7 handed to timer 1 by ACR
    # bit 7.
    def port_b_output
      lines = driven_lines(@orb, @ddrb)
      return lines unless @acr.anybits?(0x80)

      @t1.pb7 ? lines | 0x80 : lines & 0x7f
    end

    # An active CA1 edge latches port A while ACR bit 0 is set.
    def ca1=(high)
      return if high == @ca.c1_high

      @latch_a = pins_a if @acr.anybits?(0x01) && @ca.active_c1_edge?(high)
      @ca.c1 = high
    end

    def ca2=(high)
      @ca.c2 = high
    end

    # An active CB1 edge latches port B while ACR bit 1 is set. CB1 also
    # clocks the shift register in its external clock modes.
    def cb1=(high)
      return if high == @cb.c1_high

      @ifr.set(InterruptRegister::SR) if @shift_register.cb1_edge!(high)
      @latch_b = pins_b if @acr.anybits?(0x02) && @cb.active_c1_edge?(high)
      @cb.c1 = high
    end

    def cb2=(high)
      @shift_register.cb2_input = high
      @cb.c2 = high
    end

    # A falling edge counts a pulse while timer 2 counts them.
    def pb6=(high)
      fell = @pb6_high && !high
      @pb6_high = high
      @ifr.set(InterruptRegister::TIMER2) if fell && @t2.pulse!
    end

    def ca2_output = @ca.c2_output

    # The shift register's clock on CB1, or nil when CB1 is an input.
    def cb1_output = @shift_register.cb1_output

    # The shift register takes CB2 over in its shift-out modes.
    def cb2_output
      level = @shift_register.cb2_output
      level.nil? ? @cb.c2_output : level
    end

    def peek(addr)
      case offset_of(addr) & 0x0f
      when 0x00 then read_port_b
      when 0x01 then read_port_a(handshake: true)
      when 0x02 then @ddrb
      when 0x03 then @ddra
      when 0x04 then read_timer_low(@t1.counter, InterruptRegister::TIMER1)
      when 0x05 then high_byte(@t1.counter)
      when 0x06 then low_byte(@t1.latch)
      when 0x07 then high_byte(@t1.latch)
      when 0x08 then read_timer_low(@t2.counter, InterruptRegister::TIMER2)
      when 0x09 then high_byte(@t2.counter)
      when 0x0a then read_shift_register
      when 0x0b then @acr
      when 0x0c then @pcr
      when 0x0d then @ifr.read
      when 0x0e then @ifr.read_enable
      else read_port_a(handshake: false)
      end
    end

    def poke(addr, value)
      case offset_of(addr) & 0x0f
      when 0x00 then write_port_b(value)
      when 0x01 then write_port_a(value, handshake: true)
      when 0x02 then @ddrb = value
      when 0x03 then @ddra = value
      when 0x04, 0x06 then @t1.write_latch_low(value)
      when 0x05 then write_timer1_high(value, start: true)
      when 0x07 then write_timer1_high(value, start: false)
      when 0x08 then @t2.latch_low = value
      when 0x09 then write_timer2_high(value)
      when 0x0a then write_shift_register(value)
      when 0x0b then write_acr(value)
      when 0x0c then write_pcr(value)
      when 0x0d then @ifr.write(value)
      when 0x0e then @ifr.write_enable(value)
      else write_port_a(value, handshake: false)
      end
    end

    private

    # Output bits are driven from the data register; input bits float high.
    # External peripherals can still pull any line low (wired-AND).
    def driven_lines(register, direction)
      (register & direction) | (~direction & 0xff)
    end

    def pins_a
      lines = port_a_output
      peripheral ? lines & peripheral.read_a(lines) : lines
    end

    def pins_b
      lines = port_b_output
      peripheral ? lines & peripheral.read_b(lines) : lines
    end

    # Port A reads the pins, or what CA1 latched off them.
    def read_port_a(handshake:)
      value = @acr.anybits?(0x01) ? @latch_a : pins_a
      @ca.access!(false) if handshake
      value
    end

    def write_port_a(value, handshake:)
      @ora = value
      @ca.access!(true) if handshake
    end

    # Port B reads its output bits from ORB, or from timer 1 for PB7, and
    # its input bits from the pins, or from what CB1 latched off them.
    def read_port_b
      outputs = @acr.anybits?(0x80) ? @ddrb | 0x80 : @ddrb
      inputs = @acr.anybits?(0x02) ? @latch_b : pins_b
      @cb.access!(false)
      (port_b_output & outputs) | (inputs & ~outputs & 0xff)
    end

    def write_port_b(value)
      @orb = value
      @cb.access!(true)
    end

    # A read of either timer's low counter byte acknowledges its interrupt.
    def read_timer_low(counter, flag)
      @ifr.clear(flag)
      low_byte(counter)
    end

    # $5 loads and starts the counter; $7 only writes the latch. Both
    # acknowledge the interrupt.
    def write_timer1_high(value, start:)
      @t1.write_latch_high(value)
      @t1.start! if start
      @ifr.clear(InterruptRegister::TIMER1)
    end

    def write_timer2_high(value)
      @t2.load(value)
      @ifr.clear(InterruptRegister::TIMER2)
    end

    def read_shift_register
      value = @shift_register.data
      @shift_register.access!
      @ifr.clear(InterruptRegister::SR)
      value
    end

    def write_shift_register(value)
      @shift_register.data = value
      @shift_register.access!
      @ifr.clear(InterruptRegister::SR)
    end

    # Bits 4-2 pick the shift register's mode. Modes 1, 4 and 5 clock off
    # timer 2's low byte. Bit 7 turning on hands PB7 to timer 1 high.
    def write_acr(value)
      @t1.pb7_enabled! if value.anybits?(0x80) && @acr.nobits?(0x80)
      @acr = value
      @t2.count_pulses = value.anybits?(0x20)
      mode = (value >> 2) & 0x07
      @shift_register.mode = mode
      @sr_uses_t2 = [1, 4, 5].include?(mode)
    end

    def write_pcr(value)
      @pcr = value
      @ca.control = value & 0x0f
      @cb.control = value >> 4
    end
  end
end
