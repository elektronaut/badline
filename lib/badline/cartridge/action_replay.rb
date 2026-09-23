# frozen_string_literal: true

module Badline
  class Cartridge
    # Action Replay v4.2 to v6: four 8K ROM banks and 8K of RAM. A write to
    # I/O 1 sets the control register:
    #
    #   bit 0    pulls GAME low
    #   bit 1    releases EXROM
    #   bit 2    switches the register off until the next freeze or reset
    #   bits 3-4 ROM bank
    #   bit 5    RAM instead of ROM at ROML and I/O 2
    #   bit 6    acknowledges a freeze and lets go of NMI
    #
    # I/O 2 shows the last page of the RAM or of the ROM bank. The register
    # doesn't decode R/W, so a read of I/O 1 writes whatever is on the bus
    # into it. RAM with only EXROM released ($22) selects the cartridge RAM
    # and the C64's together at ROML. A freeze switches the cartridge back
    # on, in Ultimax mode with the RAM at ROML and the first bank at ROMH.
    class ActionReplay < Cartridge
      include Freezer

      CONTROL_MODES = %i[rom8k rom16k off ultimax].freeze
      IO2_PAGE = 0x1f00

      def connect(ram:, open_bus:)
        super
        @through.backing = ram
        @contended.backing = ram
      end

      def readable_io_pages
        [0xde, 0xdf]
      end

      def peek(addr)
        return open_bus(addr) unless @active
        return io2_peek(addr) if addr >= 0xdf00

        open_bus(addr).tap { |value| control(value) }
      end

      def poke(addr, value)
        return unless @active

        if addr < 0xdf00
          control(value)
        elsif @io2_ram
          @ram_data[IO2_PAGE | (addr & 0xff)] = value
        end
      end

      def reset
        @active = true
        self.nmi = false
        control(0)
      end

      def freeze!
        @active = true
        @rom = bank(@rom_banks, 0)
        select(:ultimax, @isolated, io2_ram: true)
      end

      private

      def io2_peek(addr)
        @io2_ram ? @ram_data[IO2_PAGE | (addr & 0xff)] : @rom.peek(addr)
      end

      def control(value)
        self.nmi = false if value.anybits?(0x40)
        @rom = bank(@rom_banks, (value >> 3) & 0x03)
        configure(value)
        @active = false if value.anybits?(0x04)
      end

      def configure(value)
        return select(:rom8k, @contended, io2_ram: true) if (value & 0x23) == 0x22

        configure_standard(value)
      end

      def configure_standard(value)
        mode = CONTROL_MODES[value & 0x03]
        if value.anybits?(0x20)
          select(mode, mode == :ultimax ? @isolated : @through, io2_ram: true)
        else
          select(mode, @rom, io2_ram: false)
        end
      end

      def select(mode, roml, io2_ram:, romh: @rom)
        self.mode = mode
        @roml = roml
        @romh = romh
        @io2_ram = io2_ram
        changed!
      end

      def install_chips(chips)
        @rom_banks = banks_from(chips).first
        @ram_data = Array.new(BANK_SIZE, 0)
        @through = RAMBank.new(@ram_data)
        @isolated = RAMBank.new(@ram_data)
        @contended = ContendedRAM.new(@ram_data)
        reset
      end
    end
  end
end
