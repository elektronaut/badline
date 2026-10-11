# frozen_string_literal: true

module Badline
  class Cartridge
    # One 8K bank of cartridge ROM. The chip decodes only the low address
    # lines, so the same bank answers at $8000, $A000 or $E000, and a smaller
    # chip mirrors across the window.
    class Bank
      def initialize(data)
        size = [1 << (data.length - 1).bit_length, 1].max
        @mask = size - 1
        @data = (data + ([0xff] * (size - data.length))).freeze
      end

      def peek(addr)
        @data[addr & @mask]
      end
      alias [] peek
    end

    # Cartridge RAM mapped into the ROML or ROMH window. Writes land in the
    # C64's RAM underneath as well, when there is a backing. Banks built on
    # the same data are views of the same RAM.
    class RAMBank
      attr_reader :data
      attr_writer :backing

      def initialize(data = Array.new(BANK_SIZE, 0))
        @data = data
        @backing = nil
      end

      def peek(addr)
        @data[addr & 0x1fff]
      end
      alias [] peek

      def poke(addr, value)
        @data[addr & 0x1fff] = value
        @backing&.poke(addr, value)
      end
      alias []= poke
    end

    # Cartridge RAM the window reads, where the cartridge ignores writes.
    class RAMReader
      def initialize(data)
        @data = data
      end

      def peek(addr)
        @data[addr & 0x1fff]
      end
      alias [] peek
    end

    # Cartridge RAM that takes writes while the window reads something else.
    class WriteOnlyRAM < RAMBank
      def initialize(data, reader)
        super(data)
        @reader = reader
      end

      def peek(addr)
        @reader.peek(addr)
      end
      alias [] peek
    end

    # Cartridge RAM selected together with the C64's RAM, both driving the
    # bus on a read. The result is ORed, as VICE has it.
    class ContendedRAM < RAMBank
      def peek(addr)
        @data[addr & 0x1fff] | @backing.peek(addr)
      end
      alias [] peek
    end

    EMPTY_BANK = Bank.new([0xff])
  end
end
