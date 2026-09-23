# frozen_string_literal: true

module Badline
  class Cartridge
    # Epyx FastLoad: 8K. A capacitor holds the ROM in for 512 cycles after
    # it was last discharged, by reset, a read through ROML or a read of
    # I/O 1; once it charges, $8000-$9FFF reads RAM. I/O 2 reads the last
    # 256 bytes of the ROM.
    class EpyxFastload < Cartridge
      DISCHARGED_CYCLES = 512

      class Window
        def initialize(cartridge, rom)
          @cartridge = cartridge
          @rom = rom
        end

        def peek(addr)
          @cartridge.rom_visible? ? @rom.peek(addr) : @cartridge.ram_peek(addr)
        end
      end

      def clock=(clock)
        super
        discharge!
      end

      def readable_io_pages
        [0xde, 0xdf]
      end

      def peek(addr)
        return @rom.peek(addr) if addr >= 0xdf00

        discharge!
        open_bus(addr)
      end

      # True while the capacitor holds the ROM in, discharging it again.
      def rom_visible?
        return true unless @clock
        return false if @clock.call - @discharged_at >= DISCHARGED_CYCLES

        discharge!
        true
      end

      def ram_peek(addr)
        @ram.peek(addr)
      end

      private

      def discharge!
        @discharged_at = @clock ? @clock.call : 0
      end

      def install_chips(chips)
        @rom = banks_from(chips).first.compact.first
        @roml = Window.new(self, @rom)
        @discharged_at = 0
        self.mode = :rom8k
      end
    end
  end
end
