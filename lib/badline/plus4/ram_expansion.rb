# frozen_string_literal: true

module Badline
  class Plus4
    # Hannes's RAM expansion, 256K or 1M in 64K banks, and Csory's 256K on
    # the same board, from Solder's register notes and the board's GAL
    # equations (plus4world, "256K RAM (Hannes)").
    #
    # The control register is a 6529 at $FD16, which reads back what was
    # written. The expansion decodes $FD10-$FD1F further, so the user port
    # answers only at $FD10, and the rest of the range is open.
    #
    # - Bits 0-1, and bits 2-3 on the 1M: the bank the CPU sees above the
    #   switch bound. All ones is the standard bank, the RAM below the
    #   bound, which bits 0-3 pick inverted: bank 3 of the 256K and bank
    #   15 of the 1M.
    # - Bit 6: the TED fetches from the CPU's bank when set, and from the
    #   standard bank when clear.
    # - Bit 7: the switch bound, $4000 when set, $1000 when clear.
    # - Bits 4-5: on the Csory board, two different bits switch Csory's
    #   mapping on (the notes' gate version; its table names 10 and its
    #   GAL 01).
    #
    # The register is all ones at power-on and after a reset, so the
    # machine starts in the standard bank, with the TED following it.
    #
    # Csory's mapping puts one 16K block of the 256K, picked by bits 0-3
    # of a write-only latch at $FD15, in the 16K window of the CPU's 64K
    # that bits 6-7 pick. The standard bank holds blocks 0-3. The TED sees
    # the block too while bit 6 of $FD16 is set. On the Csory board the
    # TED reads the KERNAL wherever it fetches from the high ROM, whichever
    # bank the ROM latch selects.
    class RAMExpansion
      # Each expansion by name: its 64K banks, and whether it has Csory's
      # mapping.
      KINDS = { hannes256: [4, false], hannes1m: [16, false], csory256: [4, true] }.freeze

      # Whose design each is, as the pause menu names it.
      NAMES = { hannes256: "HANNES", hannes1m: "HANNES", csory256: "CSORY" }.freeze

      CONTROL = 0x06
      CSORY_LATCH = 0x05

      # The register at $FD16, and Csory's latch at $FD15.
      attr_reader :kind, :control, :csory_latch

      # +ram+ is the machine's own 64K, the standard bank, and +view+ the
      # Bus::MirroredRAM the bus reads it through.
      def initialize(kind, ram, view)
        @kind = kind
        count, csory = KINDS.fetch(kind)
        @csory = csory
        @mask = count - 1
        size = (count - 1) * 0x10000
        @extra = Memory.new(Array.new(size, Bus::RAM_POWER_ON), length: size, start: 0)
        @banks = [view] + Array.new(count - 1) { |index| Bus::MirroredRAM.new(@extra, 0xffff, index * 0x10000) }
        @blocks = csory ? Array.new(16) { |block| block_view(ram, block) } : []
        @control = 0xff
        @csory_latch = 0
      end

      # The size in K.
      def size_kb = (@mask + 1) * 64

      # Whether the TED reads the KERNAL for the whole high ROM.
      def kernal_for_ted? = @csory

      # A write to $FD11-$FD1F: the control register at $FD16, and on the
      # Csory board, Csory's latch at $FD15.
      def poke(addr, value)
        case addr & 0x0f
        when CONTROL then @control = value
        when CSORY_LATCH then @csory_latch = value if @csory
        end
      end

      # The RESET line sets the register, as power-on does. Csory's latch
      # keeps its value.
      def reset!
        @control = 0xff
      end

      def power_on!
        @extra.clear!(Array.new(@extra.length, Bus::RAM_POWER_ON))
        @csory_latch = 0
        reset!
      end

      # Lays the RAM the CPU sees out in +cpu+ and the RAM the TED sees in
      # +ted+, a view for each of the 256 pages.
      def map(cpu, ted)
        control = @control
        bound = control.anybits?(0x80) ? 0x40 : 0x10
        standard = @banks[0]
        cpu.fill(standard, 0x00, bound)
        cpu.fill(@banks[~control & @mask], bound, 0x100 - bound)
        follows = control.anybits?(0x40)
        if follows
          page = 0
          while page < 0x100
            ted[page] = cpu[page]
            page += 1
          end
        else
          ted.fill(standard, 0x00, 0x100)
        end
        return unless csory_on?

        latch = @csory_latch
        block = @blocks[latch & 0x0f]
        window = (latch >> 6) * 0x40
        cpu.fill(block, window, 0x40)
        ted.fill(block, window, 0x40) if follows
      end

      # The banks beyond the standard one, and Csory's latch, in a keyed
      # snapshot module (BL-RAMEXP).
      def save_fields(out)
        out.int("control", @control)
        out.int("csory_latch", @csory_latch) if @csory
        @extra.save_fields(out, "ram")
      end

      def load_fields(input)
        @control = input.byte("control", @control)
        @csory_latch = input.byte("csory_latch", @csory_latch)
        @extra.load_fields(input, "ram")
      end

      private

      def csory_on?
        control = @control
        @csory && control.anybits?(0x10) != control.anybits?(0x20)
      end

      # Block +block+ of the 256K, from the standard bank's four on.
      def block_view(ram, block)
        return Bus::MirroredRAM.new(ram, 0x3fff, block * 0x4000) if block < 4

        Bus::MirroredRAM.new(@extra, 0x3fff, (block - 4) * 0x4000)
      end
    end
  end
end
