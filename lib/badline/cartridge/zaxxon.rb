# frozen_string_literal: true

module Badline
  class Cartridge
    # Zaxxon / Super Zaxxon: 16K mode with a 4K ROML mirrored across
    # $8000-$9FFF and two 8K ROMH banks. A read through ROML selects the
    # ROMH bank: $8000-$8FFF the first, $9000-$9FFF the second.
    class Zaxxon < Cartridge
      class Low
        def initialize(rom, high)
          @rom = rom
          @high = high
        end

        def peek(addr)
          @high.select(addr[12])
          @rom.peek(addr)
        end
      end

      class High
        def initialize(banks)
          @banks = banks
          select(0)
        end

        def select(number)
          @bank = @banks[number] || EMPTY_BANK
        end

        def peek(addr)
          @bank.peek(addr)
        end
      end

      private

      def install_chips(chips)
        roml, romh = banks_from(chips)
        @romh = High.new(romh)
        @roml = Low.new(roml.first || EMPTY_BANK, @romh)
        self.mode = :rom16k
      end
    end
  end
end
