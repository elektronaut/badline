# frozen_string_literal: true

module Badline
  class C64
    class Cartridge
      # Dinamic: up to 16 8K banks. Reading $DE00-$DE0F selects the bank from
      # the low address bits.
      class Dinamic < Cartridge
        def readable_io_pages
          [0xde]
        end

        def peek(addr)
          if addr < 0xde10
            @bank = addr & 0x0f
            @roml = bank(@banks, @bank)
            changed!
          end
          open_bus(addr)
        end

        def reset
          @bank = 0
          @roml = bank(@banks, 0)
          changed!
        end

        private

        def install_chips(chips)
          @banks = banks_from(chips).first
          self.mode = :rom8k
          reset
        end
      end
    end
  end
end
