# frozen_string_literal: true

module Badline
  class REU
    # One transfer between the C64 and the REU's RAM, clocked a cycle at a
    # time while the REC holds the bus. The REC only reads the C64's bus
    # while BA is high, so a read followed by BA low waits for BA to rise.
    # After a write it goes on through the first BA-low cycle and stops at
    # the second. See doc/pinned-behaviour.md, REU DMA.
    class DMA
      # Transfer types, as the command register's bottom two bits give
      # them.
      STASH = 0
      FETCH = 1
      SWAP = 2
      VERIFY = 3

      # What the REC did on the cycle before.
      IDLE = 0
      READ = 1
      WRITE = 2

      # Where the transfer stopped, what it left for the length register,
      # and the status bits it ended with.
      attr_reader :c64, :expansion, :length, :events

      def initialize(ram, span, bus)
        @ram = ram
        @span = span
        @bus = bus
        @c64 = @expansion = @length = @events = 0
        @holding = false
      end

      # Whether the REC held the bus on the last cycle clocked, which it
      # does while it waits for BA too, since the CPU stays halted.
      def holds_bus? = @holding

      # A length of 0 moves 64K. control is the address control register,
      # which can hold either address where it is.
      def start(type, c64, expansion, length, control)
        @type = type
        @c64 = c64
        @expansion = expansion
        @length = length.zero? ? 0x10000 : length
        @c64_step = control.anybits?(FIX_C64) ? 0 : 1
        @expansion_step = control.anybits?(FIX_EXPANSION) ? 0 : 1
        @events = 0
        @holding = true
        @last = IDLE
        @waiting = false
        @ba_low_after_writes = 0
        @stopped_after_write = false
        @swap_write_due = false
        @swap_read_again = false
        @swap_byte = 0
        @held_read = 0
        @moved_all = false
        @extra_cycle = false
      end

      # One cycle of the transfer. The cycle the REC lets go of the bus on
      # is the CPU's. late says BA fell on this cycle but a REC that moved a
      # byte on the last one doesn't see it yet (VIC#reu_ba_late?), and
      # handed_on that BA runs on from a bad line's DMA into a sprite's
      # here (VIC#reu_ba_handed_on?).
      def cycle!(ba_low, late, handed_on)
        note_ba(ba_low, late)
        @swap_read_again ||= handed_on && @swap_write_due
        settle_held_read(ba_low) if @held_read.positive?
        return if @waiting && ba_low

        @waiting = false
        @moved_all ? wind_down : move(ba_low)
      end

      # Everything a transfer holds between cycles. Before the first
      # transfer, the fields it sets on starting are empty.
      def save_state(out)
        out.int(@c64).int(@expansion).int(@length).int(@events)
        [@type, @c64_step, @expansion_step, @last, @ba_low_after_writes, @swap_byte, @held_read].each do |value|
          out.optional_int(value)
        end
        [@holding, @waiting, @stopped_after_write, @swap_write_due, @moved_all, @extra_cycle].each do |flag|
          out.boolean(flag)
        end
      end

      def load_state(input)
        @c64 = input.int
        @expansion = input.int
        @length = input.int
        @events = input.int
        load_steps(input)
        @holding = input.boolean?
        @waiting = input.boolean?
        @stopped_after_write = input.boolean?
        @swap_write_due = input.boolean?
        @moved_all = input.boolean?
        @extra_cycle = input.boolean?
      end

      private

      def load_steps(input)
        @type = input.optional_int
        @c64_step = input.optional_int
        @expansion_step = input.optional_int
        @last = input.optional_int
        @ba_low_after_writes = input.optional_int
        @swap_byte = input.optional_int
        @held_read = input.optional_int
      end

      # The second BA-low cycle in a row after writes stops the REC, and so
      # does any BA-low cycle after a read. It then waits for BA to rise.
      def note_ba(ba_low, late)
        seen = ba_low && !late
        if @last == READ
          note_ba_after_read(seen)
        elsif @last == WRITE
          note_ba_after_write(seen)
        end
        @last = IDLE
      end

      # A swap's read that BA stops before its write is made again.
      def note_ba_after_read(ba_low)
        @waiting = ba_low
        @ba_low_after_writes = 0
        @swap_read_again = ba_low && @swap_write_due && @held_read.zero?
      end

      # A fetch's last write doesn't go through the first BA-low cycle.
      # Pinned by REU/reutiming2/d and d2.
      def note_ba_after_write(ba_low)
        @ba_low_after_writes = ba_low ? @ba_low_after_writes + 1 : 0
        @stopped_after_write = @ba_low_after_writes == 2 || (ba_low && @type == FETCH && @length == 1)
        return unless @stopped_after_write

        @waiting = true
        @ba_low_after_writes = 0
      end

      # A fetch or a swap whose last write ran into BA, or a verify that
      # found a difference before its last byte, takes one more cycle before
      # the REC lets go of the bus.
      def wind_down
        if @extra_cycle || (@stopped_after_write && (@type == FETCH || @type == SWAP))
          @extra_cycle = @stopped_after_write = false
          @last = READ
          return
        end

        @holding = false
        settle
      end

      def move(ba_low)
        case @type
        when STASH then stash
        when FETCH then fetch
        when SWAP then swap(ba_low)
        else verify
        end
      end

      # The REU's data bus latch keeps the last byte the REC stored.
      def stash
        byte = read_c64
        @ram.poke(@expansion, byte)
        @ram.latch = byte
        step
        @last = READ
      end

      def fetch
        byte = @ram.peek(@expansion)
        @ram.latch = byte
        write_c64(byte)
        step
        @last = WRITE
      end

      # Two cycles a byte: the C64's byte is read and stored while the
      # REU's is fetched, and the REU's is written to the C64 on the next.
      def swap(ba_low)
        return read_swap_again if @swap_read_again

        if @swap_write_due
          @swap_write_due = false
          write_c64(@swap_byte)
          step
          @last = WRITE
          return
        end

        @swap_byte = @ram.peek(@expansion)
        @swap_write_due = true
        @last = READ
        return swap_read_on_ba if ba_low

        @ram.poke(@expansion, read_c64)
      end

      # A swap's read on the first BA-low cycle after a write, while AEC is
      # still high. On the last byte the read is made there, the write
      # follows on the next cycle whatever BA does, and the REC lets go.
      # Otherwise the read stays open and takes what is on the bus two
      # cycles later, or on the cycle BA rises if that comes first. Pinned
      # by REU/reutiming2/e5-m2, f3-m2 and f4-m2.
      def swap_read_on_ba
        return @held_read = 2 unless @length == 1

        @ram.poke(@expansion, read_c64)
        @last = IDLE
        @ba_low_after_writes = 0
      end

      # A swap's read that BA cut off from its write is made again when BA
      # rises, and the write follows it. Pinned by REU/reutiming2/e4-m2,
      # e6-m2 and g3-m2.
      def read_swap_again
        @swap_read_again = false
        @ram.poke(@expansion, read_c64)
        @last = READ
      end

      def settle_held_read(ba_low)
        @held_read -= 1
        return if @held_read.positive? && ba_low

        @held_read = 0
        @ram.poke(@expansion, read_c64)
      end

      # A difference ends the transfer, with one cycle more if bytes were
      # left to compare.
      def verify
        same = @ram.peek(@expansion) == read_c64
        step
        @last = READ
        return if same

        @events |= FAULT
        @extra_cycle = @length.positive?
        @moved_all = true
      end

      # The REC reaches C64 memory as the CPU sees it, but at $00 and $01
      # it reaches the RAM under the CPU's port.
      def read_c64
        @c64 < 0x02 ? @bus.ram.peek(@c64) : @bus.peek(@c64)
      end

      def write_c64(byte)
        @c64 < 0x02 ? @bus.ram.poke(@c64, byte) : @bus.poke(@c64, byte)
      end

      # The REC counts the expansion address in its 19 low bits, from the
      # top of its span back to 0, and leaves the bank bits above them as
      # they were.
      def step
        @c64 = (@c64 + @c64_step) & 0xffff
        low = (@expansion & 0x7ffff) + @expansion_step
        @expansion = (@expansion & 0xf80000) | (low == @span ? 0 : low)
        @length -= 1
        @moved_all = true if @length.zero?
      end

      # The length register is left at 1 after a whole block. A fetch has
      # already fetched the byte after its last into the latch.
      def settle
        return settle_verify if @type == VERIFY

        @length += 1
        @events |= END_OF_BLOCK
        @ram.latch = @ram.peek(@expansion) if @type == FETCH
      end

      # A verify that compared every byte ends the block. One that found a
      # difference on the byte before the last compares the last too, and
      # ends the block if that one is the same.
      def settle_verify
        if @length.zero?
          @length = 1
          @events |= END_OF_BLOCK
        elsif @length == 1 && @ram.peek(@expansion) == read_c64
          @events |= END_OF_BLOCK
        end
      end
    end
  end
end
