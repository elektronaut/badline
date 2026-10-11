# frozen_string_literal: true

module Badline
  class Z80
    # The machine cycles that reach the bus. An opcode fetch (M1) takes 4
    # T-states and refreshes a row of DRAM, which counts up the low 7 bits
    # of R. A memory read or write takes 3, and an I/O read or write 4,
    # one of them the wait state the Z80 inserts itself. Each calls the bus
    # on its first T-state, and T-states the CPU spends inside lengthen
    # the machine cycle before them.
    module BusCycles
      private

      def fetch_opcode
        opcode = @bus.fetch(@pc)
        @pc = (@pc + 1) & 0xffff
        refresh
        @cycles += 4
        opcode
      end

      # A halted CPU fetches from the address after HALT, again and again,
      # and leaves the program counter there.
      def idle_fetch
        @bus.fetch(@pc)
        refresh
        @cycles += 4
      end

      def refresh
        @r = (@r & 0x80) | ((@r + 1) & 0x7f)
      end

      def read_byte(address)
        value = @bus.read(address)
        @cycles += 3
        value
      end

      def write_byte(address, value)
        @bus.write(address, value)
        @cycles += 3
      end

      def read_word(address)
        low = read_byte(address)
        low | (read_byte((address + 1) & 0xffff) << 8)
      end

      def write_word(address, value)
        write_byte(address, value & 0xff)
        write_byte((address + 1) & 0xffff, value >> 8)
      end

      def input(port)
        value = @bus.input(port)
        @cycles += 4
        value
      end

      def output(port, value)
        @bus.output(port, value)
        @cycles += 4
      end

      # The byte after the opcode.
      def fetch_byte
        value = read_byte(@pc)
        @pc = (@pc + 1) & 0xffff
        value
      end

      def fetch_word
        low = fetch_byte
        low | (fetch_byte << 8)
      end

      def push(value)
        @sp = (@sp - 1) & 0xffff
        write_byte(@sp, value >> 8)
        @sp = (@sp - 1) & 0xffff
        write_byte(@sp, value & 0xff)
      end

      def pop
        low = read_byte(@sp)
        high = read_byte((@sp + 1) & 0xffff)
        @sp = (@sp + 2) & 0xffff
        low | (high << 8)
      end

      # The address of an (HL) operand, or of (IX+d), whose displacement is
      # read from after the opcode and added in 5 T-states inside.
      def operand_address
        return hl if @prefix.zero?

        displaced
        @cycles += 5
        @wz
      end

      # Reads the displacement of an (IX+d) or (IY+d) operand and leaves
      # the address in WZ.
      def displaced
        offset = fetch_byte
        offset -= 256 if offset > 127
        @wz = (index_register + offset) & 0xffff
      end
    end
  end
end
