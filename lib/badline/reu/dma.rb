# frozen_string_literal: true

module Badline
  class REU
    # One transfer between the C64 and the REU's RAM, clocked a cycle at a
    # time while the REC holds the bus. It follows the VIC's BA line the
    # way VICE's x64sc does: after reading C64 memory the REC waits out
    # every BA-low cycle, and after writing it goes on through the first
    # and waits from the second.
    class DMA
      # Transfer types.
      TO_REU = 0
      TO_C64 = 1
      SWAP = 2
      VERIFY = 3

      # The cycles a swap's read on BA low is held open for.
      HELD_READ_CYCLES = 2

      # What the access just made asks of the next cycle.
      NO_ACCESS = 0
      READ_ACCESS = 1
      WRITE_ACCESS = 2

      # Where the transfer stopped, what it left in the length register
      # and the status bits it ended with.
      attr_reader :host, :target, :remaining, :result

      def initialize(ram, wrap)
        @ram = ram
        @wrap = wrap
        @bus = nil
        @host = @target = @remaining = @result = 0
        @holding = false
      end

      # Whether the REC held the bus on the last cycle clocked, which it
      # does even while it waits out the VIC, since the CPU stays halted.
      def holds_bus? = @holding

      def connect(bus)
        @bus = bus
      end

      # A length of 0 moves 64K. control is the address control register,
      # which can keep either side's address fixed.
      def start(mode, host, target, length, control)
        @mode = mode
        @host = host
        @target = target
        @remaining = length.zero? ? 0x10000 : length
        @host_step = control.anybits?(FIX_C64) ? 0 : 1
        @reu_step = control.anybits?(FIX_REU) ? 0 : 1
        @holding = true
        @result = 0
        @after = NO_ACCESS
        @delay = 0
        @last_cycle = false
        @stealing = false
        @swap_write = false
        @swap_value = 0
        @held_read = 0
        @finished = false
        @extra_cycle = false
      end

      # Clocks the transfer for one cycle. The cycle it hands the bus back
      # on is the CPU's.
      def cycle!(ba_low)
        follow_access(ba_low)
        hold_read(ba_low) if @held_read.positive?
        if @stealing
          return if ba_low

          @stealing = false
        end
        @finished ? finish_cycle : access(ba_low)
      end

      private

      def follow_access(ba_low)
        case @after
        when READ_ACCESS
          @stealing = true if ba_low
        when WRITE_ACCESS
          @delay = ba_low ? @delay + 1 : 0
          @last_cycle = @delay > 1
          if @last_cycle
            @stealing = true
            @delay = 0
          end
        end
        @after = NO_ACCESS
      end

      # After the last byte the REC takes one more cycle if it was waiting
      # out the VIC when a write ended the transfer, or after a verify
      # error that left bytes uncompared. Then it hands the bus back.
      def finish_cycle
        if @extra_cycle || (@last_cycle && (@mode == TO_C64 || @mode == SWAP))
          @extra_cycle = false
          @last_cycle = false
          @after = READ_ACCESS
          return
        end

        @holding = false
        finish
      end

      def access(ba_low)
        case @mode
        when TO_REU then access_to_reu
        when TO_C64 then access_to_c64
        when SWAP then access_swap(ba_low)
        else access_verify
        end
      end

      # The last byte written stays in the latch.
      def access_to_reu
        value = read_c64
        @ram.poke(@target, value)
        @ram.latch = value
        advance
        @after = READ_ACCESS
      end

      def access_to_c64
        value = @ram.peek(@target)
        @ram.latch = value
        write_c64(value)
        advance
        @after = WRITE_ACCESS
      end

      # A swap takes two cycles a byte: the C64 byte is read as the REU's
      # goes into the latch, and the REU's is written back on the next.
      def access_swap(ba_low)
        if @swap_write
          @swap_write = false
          write_c64(@swap_value)
          advance
          @after = WRITE_ACCESS
        else
          @swap_value = @ram.peek(@target)
          @swap_write = true
          @after = READ_ACCESS
          return swap_read_on_ba(@remaining == 1) if ba_low

          @ram.poke(@target, read_c64)
        end
      end

      # A swap's read can fall on the first BA-low cycle, after a write,
      # while AEC is still high. The last byte's read is made there and its
      # write follows on the next cycle, after which the REC hands the bus
      # back. Any other read is held open and takes the byte on the bus two
      # cycles later, or when BA rises first. Pinned by
      # REU/reutiming2/e5-m2, f3-m2 and f4-m2.
      def swap_read_on_ba(last)
        return @held_read = HELD_READ_CYCLES unless last

        @ram.poke(@target, read_c64)
        @after = NO_ACCESS
        @delay = 0
      end

      def hold_read(ba_low)
        @held_read -= 1
        return unless @held_read.zero? || !ba_low

        @held_read = 0
        @ram.poke(@target, read_c64)
      end

      # A verify error ends the transfer, with one more cycle if any bytes
      # were left to compare.
      def access_verify
        expected = @ram.peek(@target)
        actual = read_c64
        advance
        @after = READ_ACCESS
        return if expected == actual

        @result |= VERIFY_ERROR
        @extra_cycle = @remaining >= 1
        @finished = true
      end

      # The REC reaches C64 memory through the CPU's memory map, except at
      # $00 and $01, where it reaches the RAM underneath the CPU's port.
      def read_c64
        @host < 0x02 ? @bus.ram.peek(@host) : @bus.peek(@host)
      end

      def write_c64(value)
        @host < 0x02 ? @bus.ram.poke(@host, value) : @bus.poke(@host, value)
      end

      def advance
        @host = (@host + @host_step) & 0xffff
        @target = next_reu_address(@target)
        @remaining -= 1
        @finished = true if @remaining.zero?
      end

      # The REC increments the low 19 bits and wraps them where the REC
      # does, leaving the latched bank bits above them alone.
      def next_reu_address(addr)
        following = (addr & 0x7ffff) + @reu_step
        following = 0 if following == @wrap
        (addr & 0xf80000) | following
      end

      # A finished transfer leaves 1 in the length register. After one to
      # the C64 the REC has already fetched the next byte into its latch.
      def finish
        return finish_verify if @mode == VERIFY

        @remaining += 1
        @result |= END_OF_BLOCK
        @ram.latch = @ram.peek(@target) if @mode == TO_C64
      end

      # A verify that compared every byte ends the block. One that failed
      # on the second-to-last byte compares the last as well, and ends the
      # block if that one matches.
      def finish_verify
        if @remaining.zero?
          @remaining = 1
          @result |= END_OF_BLOCK
        elsif @remaining == 1
          @result |= END_OF_BLOCK if @ram.peek(@target) == read_c64
        end
      end
    end
  end
end
