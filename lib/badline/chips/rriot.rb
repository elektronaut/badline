# frozen_string_literal: true

require "badline/chips/riot"
require "badline/chips/rriot/keyed_state"

module Badline
  module Chips
    # The MOS 6530 RRIOT (ROM, RAM, I/O, Timer): 1 KB of mask ROM, 64 bytes
    # of RAM, two 8-bit ports, A and B, each with a direction register, a 1
    # making the pin an output, and the 6532's interval timer (RIOT::Timer).
    # It has no edge detector. The 8050 and 8250's floppy controller has
    # one, its ROM the controller's program, and the KIM-1 two. Its timer
    # reads its counter as the 6532's does, but a read after the flag sets
    # puts the prescaler back (RIOT::Timer).
    #
    # Which addresses select the ROM, the RAM and the registers is part of
    # the mask, so the board decodes them and calls read_rom (A9-A0),
    # read_ram and write_ram (A5-A0), or peek and poke (A3-A0). With A2 low,
    # A1-A0 pick port A, DDRA, port B and DDRB. With A2 high, a write loads
    # the timer, A1-A0 picking the divider, and a read with A0 low reads the
    # timer and one with A0 high the interrupt flag in bit 7, the other bits
    # 0. A3 is the timer's interrupt enable on every timer access.
    #
    # Both ports read their output bits from the output register and their
    # input bits from the pins. An input pin floats high, and a peripheral
    # pulls lines low through read_a and read_b, as a VIA's does.
    #
    # The timer's interrupt comes out on PB7, which the mask can give to it:
    # PB7 then reads low while the flag is up with its interrupt enabled,
    # and the board takes IRQ from irq?. PB5 and PB6 can be chip selects
    # instead of port lines, which the board decodes.
    class RRIOT
      attr_reader :peripheral, :timer, :ram, :rom

      # +rom+ is the 1024 bytes of the mask ROM.
      def initialize(rom:, peripheral: nil, irq_on_pb7: true)
        @rom = rom
        @peripheral = peripheral
        @irq_on_pb7 = irq_on_pb7
        @ram = Array.new(64, 0)
        @timer = RIOT::Timer.new(read_restores_divider: true)
        reset!
      end

      # The RES line clears the four I/O registers, which leaves every line
      # an input, and disables the interrupt. The timer counts on.
      def reset!
        @ora = @orb = @ddra = @ddrb = 0x00
        @timer.irq_enabled = false
      end

      def irq? = @irq_on_pb7 && @timer.irq?

      def cycle!
        @timer.cycle!
      end

      # Port A as driven by ORA and DDRA, input lines floating high.
      def port_a_output = driven_lines(@ora, @ddra)

      # Port B as driven by ORB and DDRB, PB7 pulled low by the interrupt.
      def port_b_output
        lines = driven_lines(@orb, @ddrb)
        irq? ? lines & 0x7f : lines
      end

      # How many cycles the RRIOT can run with no counter pulling IRQ.
      def quiet_cycles = @timer.quiet_cycles

      # Runs +cycles+ cycles at once, which moves only the timer.
      def fast_forward(cycles)
        @timer.fast_forward(cycles)
      end

      # Everything the RRIOT holds but its timer's counter, for comparing
      # it at two points.
      def idle_state = [*@ram, *port_state]

      # The ports and the timer but for its counter.
      def port_state = [@ora, @orb, @ddra, @ddrb, *@timer.state, @timer.flag]

      def read_rom(addr) = @rom[addr & 0x3ff]

      def read_ram(addr) = @ram[addr & 0x3f]

      def write_ram(addr, value)
        @ram[addr & 0x3f] = value
      end

      def peek(addr)
        return read_timer(addr) if addr.anybits?(0x04)

        case addr & 0x03
        when 0x00 then read_port_a
        when 0x01 then @ddra
        when 0x02 then read_port_b
        else @ddrb
        end
      end

      def poke(addr, value)
        return @timer.write(value, addr & 0x03, addr.anybits?(0x08)) if addr.anybits?(0x04)

        case addr & 0x03
        when 0x00 then @ora = value
        when 0x01 then @ddra = value
        when 0x02 then @orb = value
        else @ddrb = value
        end
      end

      private

      def driven_lines(register, direction)
        (register & direction) | (~direction & 0xff)
      end

      def read_port_a
        lines = port_a_output
        lines &= @peripheral.read_a(lines) if @peripheral
        (@ora & @ddra) | (lines & ~@ddra & 0xff)
      end

      def read_port_b
        lines = port_b_output
        lines &= @peripheral.read_b(lines) if @peripheral
        (@orb & @ddrb) | (lines & ~@ddrb & 0xff)
      end

      def read_timer(addr)
        return @timer.read(addr.anybits?(0x08)) if addr.nobits?(0x01)

        @timer.flag ? 0x80 : 0x00
      end
    end
  end
end
