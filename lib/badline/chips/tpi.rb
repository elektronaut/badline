# frozen_string_literal: true

require "badline/chips/tpi/keyed_state"

module Badline
  module Chips
    # The MOS 6525 TPI (tri-port interface): three 8-bit ports, A, B and C,
    # each with a direction register, a 1 making the pin an output. Its
    # three address lines repeat the eight registers every 8 bytes:
    #
    # 0 - PRA
    # 1 - PRB
    # 2 - PRC, or in mode 1 the interrupt latches (bits 0-4) and the levels
    #     of IRQ, CA and CB (bits 5-7)
    # 3 - DDRA
    # 4 - DDRB
    # 5 - DDRC, or in mode 1 the interrupt mask (bits 0-4, 1 enabling)
    # 6 - CR: bit 0 MC, the mode, bit 1 IP, the priority, bits 2-3 IE3 and
    #     IE4, the active edges of I3 and I4 (1 rising), bits 4-5 CA's mode
    #     and bits 6-7 CB's
    # 7 - AIR, the active interrupt register, in mode 1
    #
    # A port reads its pins: an output's level, and what the peripheral
    # lets through of an input, which floats high (read_a, read_b and
    # read_c pull lines low, as a VIA's peripheral does).
    #
    # In mode 1 PC0-PC4 are the interrupt inputs I0-I4 (#interrupt_line).
    # A falling edge on I0-I2, or the edge IE3 and IE4 pick on I3 and I4,
    # sets the input's latch whether or not its mask bit is set. A write of
    # 0 to a latch's bit of PRC clears it, and a 1 does nothing. PC5 is
    # the IRQ output, open drain, low (#irq?) while the AIR holds a bit;
    # PC6 is CA and PC7 CB (#ca?, #cb?).
    #
    # Without priority (IP 0), the AIR holds every unmasked latch that is
    # set, and a read of it clears them and it. With priority (IP 1) the
    # inputs rank I4 > I3 > I2 > I1 > I0, and the AIR holds the one highest
    # unmasked latch that outranks the interrupt in service, the top of a
    # five-level stack. A read of the AIR pushes it on the stack, clears it
    # and its latch, and lets IRQ go; a write pops the stack, letting lower
    # interrupts through again.
    #
    # CA: 00 set high by I3's active edge and low by a read of PRA, 01
    # pulsed low by a read of PRA, 10 low, 11 high. CB: 00 set low by a
    # write of PRB and high by I4's active edge, 01 pulsed low by a write of
    # PRB, 10 low, 11 high. A pulse is shorter than a cycle, so CA and CB
    # read high in mode 01.
    #
    # The rules are the MPS 6525 datasheet's (Commodore Semiconductor
    # Group), pages 2-81 to 2-83.
    class TPI
      STACK_DEPTH = 5

      attr_reader :peripheral, :latches, :mask, :control, :stack

      def initialize(peripheral: nil)
        @peripheral = peripheral
        @lines = 0x1f
        @stack = []
        reset!
      end

      # The RES pin clears every register: mode 0, and every pin an input.
      def reset!
        @pra = @prb = @prc = 0
        @ddra = @ddrb = @ddrc = 0
        @control = 0
        @latches = 0
        @mask = 0
        @air = 0
        @stack.clear
        @ca = @cb = false
      end

      # Whether IRQ is pulled low.
      def irq? = @air != 0

      # The levels of CA and CB in mode 1.
      def ca? = @ca

      def cb? = @cb

      # The port lines as the chip drives them, inputs floating high.
      def port_a_output = driven(@pra, @ddra)

      def port_b_output = driven(@prb, @ddrb)

      def port_c_output = mode1? ? pins_c_mode1 : driven(@prc, @ddrc)

      # Something outside drives interrupt input +index+, I0 to I4, +high+
      # or low. Its active edge sets its latch in mode 1.
      def interrupt_line(index, high)
        bit = 1 << index
        was_high = @lines.anybits?(bit)
        return if was_high == high

        @lines = high ? @lines | bit : @lines & ~bit
        return unless mode1? && high == rising_active?(index)

        @latches |= bit
        @ca = true if index == 3 && ca_mode.zero?
        @cb = true if index == 4 && cb_mode.zero?
        update_air
      end

      def peek(addr)
        case addr & 0x07
        when 0 then read_pra
        when 1 then pins(@prb, @ddrb, @peripheral ? @peripheral.read_b(port_b_output) : 0xff)
        when 2 then mode1? ? pins_c_mode1 : read_pins_c
        when 3 then @ddra
        when 4 then @ddrb
        when 5 then mode1? ? @mask : @ddrc
        when 6 then @control
        else read_air
        end
      end

      def poke(addr, value)
        case addr & 0x07
        when 0 then @pra = value
        when 1 then write_prb(value)
        when 2 then write_prc(value)
        when 3 then @ddra = value
        when 4 then @ddrb = value
        when 5 then write_ddrc(value)
        when 6 then write_control(value)
        else pop_air
        end
      end

      private

      def mode1? = @control.anybits?(0x01)

      def priority? = @control.anybits?(0x02)

      def ca_mode = (@control >> 4) & 0x03

      def cb_mode = (@control >> 6) & 0x03

      # I3 and I4 latch on the edge IE3 and IE4 pick, the others falling.
      def rising_active?(index)
        case index
        when 3 then @control.anybits?(0x04)
        when 4 then @control.anybits?(0x08)
        else false
        end
      end

      def driven(register, direction) = (register & direction) | (~direction & 0xff)

      def pins(register, direction, inputs) = (register & direction) | (inputs & ~direction & 0xff)

      def read_pra
        @ca = false if mode1? && ca_mode.zero?
        pins(@pra, @ddra, @peripheral ? @peripheral.read_a(port_a_output) : 0xff)
      end

      def read_pins_c
        pins(@prc, @ddrc, @peripheral ? @peripheral.read_c(port_c_output) : 0xff)
      end

      # The latches, IRQ's level, CA's and CB's.
      def pins_c_mode1
        @latches | (irq? ? 0 : 0x20) | (@ca ? 0x40 : 0) | (@cb ? 0x80 : 0)
      end

      def write_prb(value)
        @prb = value
        @cb = false if mode1? && cb_mode.zero?
      end

      def write_prc(value)
        return @prc = value unless mode1?

        @latches &= value | 0xe0
        update_air
      end

      def write_ddrc(value)
        return @ddrc = value unless mode1?

        @mask = value & 0x1f
        update_air
      end

      def write_control(value)
        @control = value
        @ca = ca_mode.anybits?(0x01) unless ca_mode.zero?
        @cb = cb_mode.anybits?(0x01) unless cb_mode.zero?
        update_air
      end

      def read_air
        value = @air
        return value unless mode1?

        @latches &= ~value
        @air = 0
        if priority?
          @stack.shift if @stack.length == STACK_DEPTH
          @stack << value
        end
        update_air
        value
      end

      def pop_air
        return unless mode1?

        @stack.pop
        update_air
      end

      # The AIR's bits from the latches, the mask and, with priority, the
      # interrupt in service.
      def update_air
        pending = mode1? ? @latches & @mask : 0
        return @air = pending unless priority?

        highest = highest_bit(pending)
        @air = highest > (@stack.last || 0) ? highest : 0
      end

      def highest_bit(bits)
        bit = 0x10
        bit >>= 1 while bit.positive? && bits.nobits?(bit)
        bit
      end
    end
  end
end
