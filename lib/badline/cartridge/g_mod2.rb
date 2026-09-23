# frozen_string_literal: true

module Badline
  class Cartridge
    # GMod2: an Am29F040 flash chip of 64 8K banks at ROML. A write to I/O 1
    # selects the bank from bits 0-5. Bit 6 selects the EEPROM, which
    # switches the ROM out, and bits 6 and 7 together enable flash writes:
    # the cartridge then asserts Ultimax on write cycles only, so reads see
    # the C64's memory and writes to $E000-$FFFF reach the flash. The EEPROM
    # isn't emulated.
    class GMod2 < Cartridge
      BANKS = 64

      attr_reader :flash

      def clock=(clock)
        super
        @flash.clock = clock
      end

      def poke(addr, value)
        return if addr > 0xdeff

        @bank = value & 0x3f
        @flash_writes = value.allbits?(0xc0)
        self.mode = value.anybits?(0x40) ? :off : :rom8k
        select_bank
      end

      def romh_writes
        @roml if @flash_writes
      end

      # Reset selects the first bank in 8K mode, and leaves the flash as it
      # is.
      def reset
        @bank = 0
        @flash_writes = false
        self.mode = :rom8k
        select_bank
      end

      private

      def select_bank
        @roml = @flash.window(@bank * BANK_SIZE)
        changed!
      end

      def install_chips(chips)
        data = Array.new(BANKS * BANK_SIZE, 0xff)
        chips.each do |chip|
          bytes = chip.data.first(BANK_SIZE)
          data[(chip.bank & 0x3f) * BANK_SIZE, bytes.length] = bytes
        end
        @flash = Flash.new(data, model: Flash::AM29F040)
        @flash.on_change { select_bank }
        reset
      end
    end
  end
end
