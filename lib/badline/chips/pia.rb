# frozen_string_literal: true

require "badline/chips/pia/control_lines"

module Badline
  module Chips
    # The MOS 6520 PIA (Peripheral Interface Adapter), the PET's two: two
    # 8-bit ports, A and B, each with a direction register, a 1 making the
    # pin an output, and a control register for its pair of control lines
    # (ControlLines). Each side has its own IRQ output, IRQA and IRQB. There
    # are no timers.
    #
    # Four registers repeat on two address lines: port A or DDRA, CRA, port
    # B or DDRB and CRB, the port or the direction register picked by bit 2
    # of its control register.
    #
    # Port A reads its pins, whatever drives them. Port B reads its output
    # bits from its output register and its input bits from the pins. An
    # input pin floats high, and a peripheral pulls lines low through
    # read_a and read_b, as a VIA's does. The control lines take levels
    # from outside through ca1= and friends.
    class PIA
      attr_reader :peripheral

      def initialize(peripheral: nil)
        @peripheral = peripheral
        @ca = ControlLines.new(strobe_on_read: true)
        @cb = ControlLines.new(strobe_on_read: false)
        reset!
      end

      # The RES line clears every register, which leaves every line an
      # input and releases both IRQs.
      def reset!
        @ora = @orb = @ddra = @ddrb = 0x00
        @ca.reset!
        @cb.reset!
      end

      def irqa? = @ca.irq?

      def irqb? = @cb.irq?

      def irq? = @ca.irq? || @cb.irq?

      def cycle!
        @ca.cycle! if @ca.pulsing?
        @cb.cycle! if @cb.pulsing?
      end

      def cra = @ca.register

      def crb = @cb.register

      # Port A as driven by ORA and DDRA, input lines floating high.
      def port_a_output = driven_lines(@ora, @ddra)

      def port_b_output = driven_lines(@orb, @ddrb)

      def ca1=(high)
        @ca.c1 = high
      end

      def ca2=(high)
        @ca.c2 = high
      end

      def cb1=(high)
        @cb.c1 = high
      end

      def cb2=(high)
        @cb.c2 = high
      end

      def ca2_output = @ca.c2_output

      def cb2_output = @cb.c2_output

      def peek(addr)
        case addr & 0x03
        when 0x00 then @ca.port_selected? ? read_port_a : @ddra
        when 0x01 then @ca.register
        when 0x02 then @cb.port_selected? ? read_port_b : @ddrb
        else @cb.register
        end
      end

      def poke(addr, value)
        case addr & 0x03
        when 0x00 then write_port_a(value)
        when 0x01 then @ca.register = value
        when 0x02 then write_port_b(value)
        else @cb.register = value
        end
      end

      private

      def driven_lines(register, direction)
        (register & direction) | (~direction & 0xff)
      end

      def read_port_a
        lines = port_a_output
        lines &= @peripheral.read_a(lines) if @peripheral
        @ca.port_read!
        lines
      end

      def read_port_b
        lines = port_b_output
        lines &= @peripheral.read_b(lines) if @peripheral
        @cb.port_read!
        (@orb & @ddrb) | (lines & ~@ddrb & 0xff)
      end

      def write_port_a(value)
        if @ca.port_selected?
          @ora = value
          @ca.port_written!
        else
          @ddra = value
        end
      end

      def write_port_b(value)
        if @cb.port_selected?
          @orb = value
          @cb.port_written!
        else
          @ddrb = value
        end
      end
    end
  end
end
