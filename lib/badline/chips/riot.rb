# frozen_string_literal: true

require "badline/chips/riot/timer"
require "badline/chips/riot/fast_forward"
require "badline/chips/riot/keyed_parts"

module Badline
  module Chips
    # The MOS 6532 RIOT (RAM, I/O, Timer): 128 bytes of RAM, two 8-bit
    # ports, A and B, each with a direction register, a 1 making the pin an
    # output, the interval timer (Timer) and an edge detector on PA7. The
    # 8050 and 8250's interface processor has two.
    #
    # The RS pin picks the RAM (read_ram and write_ram, A6-A0) or the
    # registers (peek and poke, A4-A0). With A2 low, A1-A0 pick port A, DDRA,
    # port B and DDRB. With A2 high, a read with A0 low reads the timer and
    # one with A0 high the interrupt flags. A write with A4 high loads the
    # timer, A1-A0 picking the divider, and one with A4 low sets the edge
    # detector, A1 the interrupt enable and A0 the active edge, rising when
    # set; its data is ignored. A3 is the timer's interrupt enable on every
    # timer access.
    #
    # Port A reads its pins, whatever drives them. Port B reads its output
    # bits from its output register and its input bits from the pins. An
    # input pin floats high, and a peripheral pulls lines low through read_a
    # and read_b, as a VIA's does. PA7 takes its level from outside through
    # pa7= as well, for the edge detector.
    #
    # The edge detector watches the level on PA7, input or output. Its
    # active edge sets the PA7 flag whether or not its interrupt is enabled,
    # and so can a change of the active edge. A read of the flags clears it.
    class RIOT
      attr_reader :peripheral, :timer, :ram

      def initialize(peripheral: nil)
        @peripheral = peripheral
        @ram = Array.new(128, 0)
        @timer = Timer.new
        @pa7_high = true
        @pa7_active = false
        @pa7_flag = false
        reset!
      end

      # The RES line clears the four I/O registers, which leaves every line
      # an input, disables both interrupts and sets the active edge to
      # falling. The timer counts on, and the flags stay as they are.
      def reset!
        @ora = @orb = @ddra = @ddrb = 0x00
        @timer.irq_enabled = false
        @edge_irq_enabled = false
        @rising_edge = false
        sense_pa7
      end

      def irq? = @timer.irq? || (@pa7_flag && @edge_irq_enabled)

      def cycle!
        @timer.cycle!
      end

      # Port A as driven by ORA and DDRA, input lines floating high.
      def port_a_output = driven_lines(@ora, @ddra)

      def port_b_output = driven_lines(@orb, @ddrb)

      # The level something outside drives on PA7.
      def pa7=(high)
        @pa7_high = high
        sense_pa7
      end

      # How many cycles the RIOT can run with no counter pulling IRQ.
      def quiet_cycles = @timer.quiet_cycles

      # Runs +cycles+ cycles at once, which moves only the timer.
      def fast_forward(cycles)
        @timer.fast_forward(cycles)
      end

      # Everything the RIOT holds but its timer's counter, for comparing it
      # at two points.
      def idle_state
        [*@ram, @ora, @orb, @ddra, @ddrb, @pa7_high, @pa7_active, @pa7_flag, @edge_irq_enabled, @rising_edge,
         *@timer.state, @timer.flag]
      end

      def read_ram(addr) = @ram[addr & 0x7f]

      def write_ram(addr, value)
        @ram[addr & 0x7f] = value
      end

      def peek(addr)
        return read_timer(addr) if addr.anybits?(0x04)

        case addr & 0x03
        when 0x00 then pins_a
        when 0x01 then @ddra
        when 0x02 then read_port_b
        else @ddrb
        end
      end

      def poke(addr, value)
        return write_timer(addr, value) if addr.anybits?(0x04)

        case addr & 0x03
        when 0x00 then @ora = value
        when 0x01 then @ddra = value
        when 0x02 then @orb = value
        else @ddrb = value
        end
        sense_pa7
      end

      private

      def driven_lines(register, direction)
        (register & direction) | (~direction & 0xff)
      end

      def pins_a
        lines = @pa7_high ? port_a_output : port_a_output & 0x7f
        @peripheral ? lines & @peripheral.read_a(lines) : lines
      end

      def read_port_b
        lines = port_b_output
        lines &= @peripheral.read_b(lines) if @peripheral
        (@orb & @ddrb) | (lines & ~@ddrb & 0xff)
      end

      # Bit 7 the timer flag, bit 6 the PA7 flag, which the read clears.
      def read_timer(addr)
        return @timer.read(addr.anybits?(0x08)) if addr.nobits?(0x01)

        value = (@timer.flag ? 0x80 : 0x00) | (@pa7_flag ? 0x40 : 0x00)
        @pa7_flag = false
        value
      end

      def write_timer(addr, value)
        if addr.anybits?(0x10)
          @timer.write(value, addr & 0x03, addr.anybits?(0x08))
        else
          @edge_irq_enabled = addr.anybits?(0x02)
          @rising_edge = addr.anybits?(0x01)
          sense_pa7
        end
      end

      # The detector is active while PA7 sits at the level its active edge
      # leads to, and becoming active sets the flag.
      def sense_pa7
        active = (@pa7_high && port_a_output.anybits?(0x80)) == @rising_edge
        @pa7_flag = true if active && !@pa7_active
        @pa7_active = active
      end
    end
  end
end
