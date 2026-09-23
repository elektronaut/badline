# frozen_string_literal: true

module Badline
  class Cartridge
    # Atomic Power, sold as Nordic Power: an Action Replay 5 with one more
    # configuration. RAM with only EXROM released and bits 2, 6 and 7 clear
    # ($22) selects 16K mode with the ROM bank at ROML and the RAM at ROMH
    # and I/O 2. Writes to that RAM don't reach the C64's. The VIC never
    # sees Ultimax mode.
    class AtomicPower < ActionReplay
      def phi1_ultimax?
        false
      end

      private

      def configure(value)
        return select(:rom16k, @rom, romh: @isolated, io2_ram: true) if (value & 0xe7) == 0x22

        configure_standard(value)
      end
    end
  end
end
