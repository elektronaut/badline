# frozen_string_literal: true

module Badline
  class Cartridge
    # Retro Replay: eight 8K ROM banks and four 8K RAM banks, with the Action
    # Replay's register at $DE00 and an extended one at $DE01. The Nordic
    # Replay (subtype 1) adds the Nordic Power configuration. The flash
    # reads only, and the clock port isn't there.
    #
    # $DE00 writes:
    #   bit 0      pulls GAME low
    #   bit 1      releases EXROM
    #   bit 2      switches the registers off until the next freeze or reset
    #   bits 3-4,7 bank
    #   bit 5      RAM instead of ROM
    #   bit 6      acknowledges a freeze: until then the cartridge stays in
    #              Ultimax mode with nothing at ROML
    #
    # $DE01 writes the bank again, and once only AllowBank (bit 1), which
    # banks the RAM in I/O as well, NoFreeze (bit 2) and the REU-compatible
    # map (bit 6), which moves the I/O RAM from I/O 2 to I/O 1 above $DE01.
    # $DE00 and $DE01 read back the bank, the write-once bits and the freeze
    # button.
    #
    # The VIC sees Ultimax mode only from a freeze to the next $DE00 write.
    #
    # The RAM at ROML takes writes only in Ultimax mode, except on the Nordic
    # Replay. With RAM and only EXROM released ($22) the Retro Replay maps
    # nothing at ROML and keeps the RAM in I/O, and the Nordic Replay maps
    # the ROM at ROML and the RAM at ROMH, as the Nordic Power does.
    class RetroReplay < Cartridge
      include Freezer

      CONTROL_MODES = %i[rom8k rom16k off ultimax].freeze
      IO1_PAGE = 0x1e00
      IO2_PAGE = 0x1f00

      def initialize(crt)
        @nordic = crt.subtype == 1
        super
      end

      def connect(ram:, open_bus:)
        super
        @through.each { |b| b.backing = ram }
        configure
      end

      def readable_io_pages
        [0xde, 0xdf]
      end

      def peek(addr)
        return open_bus(addr) unless @active

        addr < 0xdf00 ? io1_peek(addr) : io2_peek(addr)
      end

      def poke(addr, value)
        return unless @active

        low = addr & 0xff
        if addr >= 0xdf00
          io_ram[IO2_PAGE | low] = value if io_ram_writable?(!@reu_mapping)
        elsif low > 1
          io_ram[IO1_PAGE | low] = value if io_ram_writable?(@reu_mapping)
        else
          low.zero? ? control(value) : extended_control(value)
        end
      end

      def phi1_ultimax?
        @phi1_ultimax
      end

      # Reset leaves the write-once bits of $DE01 as they are.
      def reset
        @active = true
        @frozen = false
        self.nmi = false
        control(0)
      end

      def freeze!
        @active = @frozen = @phi1_ultimax = true
        @ram_enabled = false
        @bank = 0
        @config = :ultimax
        configure
      end

      private

      def freeze_allowed?
        !@no_freeze
      end

      def status
        ((@bank & 0x03) << 3) | ((@bank & 0x04) << 5) |
          (@allow_bank ? 0x02 : 0) | (button_pressed? ? 0x04 : 0) | (@reu_mapping ? 0x40 : 0)
      end

      def io1_peek(addr)
        return status if (addr & 0xff) < 2
        return open_bus(addr) unless @reu_mapping && !@frozen

        io_window(addr, IO1_PAGE)
      end

      def io2_peek(addr)
        return open_bus(addr) if @reu_mapping || @frozen

        io_window(addr, IO2_PAGE)
      end

      # The I/O RAM when selected, otherwise the ROM, which 16K and Ultimax
      # mode leave out.
      def io_window(addr, page)
        if @ram_enabled || @ram_at_a000
          io_ram[page | (addr & 0xff)]
        elsif @config == :rom8k || @config == :off
          @rom.peek(addr)
        else
          open_bus(addr)
        end
      end

      def io_ram
        @ram_data[ram_view_bank]
      end

      def io_ram_writable?(window)
        window && !@frozen && (@ram_enabled || (@nordic && @ram_at_a000))
      end

      def ram_view_bank
        @allow_bank ? @bank & 0x03 : 0
      end

      def control(value)
        @bank = bank_bits(value)
        @phi1_ultimax = false
        @config = CONTROL_MODES[value & 0x03]
        @ram_at_a000 = (value & 0x67) == 0x22
        if @nordic && @ram_at_a000
          @config = :rom16k
          @ram_enabled = false
        else
          acknowledge_freeze if value.anybits?(0x40)
          @ram_enabled = value.anybits?(0x20)
          @config = :off if @ram_at_a000
        end
        @config = :ultimax if @frozen
        configure
        @active = false if value.anybits?(0x04)
      end

      def acknowledge_freeze
        @frozen = false
        self.nmi = false
      end

      def extended_control(value)
        unless @write_once
          @allow_bank = value.anybits?(0x02)
          @no_freeze = value.anybits?(0x04)
          @reu_mapping = value.anybits?(0x40)
          @write_once = true
        end
        @bank = bank_bits(value)
        configure
      end

      def bank_bits(value)
        ((value >> 3) & 0x03) | ((value >> 5) & 0x04)
      end

      def configure
        self.mode = @config
        @rom = bank(@rom_banks, @bank)
        @roml = roml_window
        @romh = romh_window
        changed!
      end

      def roml_window
        nothing = @open_bus || EMPTY_BANK
        return @ram_enabled ? WriteOnlyRAM.new(@ram_data[@bank & 0x03], nothing) : nothing if @frozen
        return ram_window(@bank & 0x03) if @ram_enabled
        return @rom if (@nordic && @ram_at_a000) || @config != :rom16k

        nothing
      end

      def ram_window(number)
        if @config == :ultimax
          @isolated[number]
        else
          (@nordic ? @through : @readers)[number]
        end
      end

      def romh_window
        nordic_ram = @nordic && @ram_at_a000
        return @isolated[ram_view_bank] if nordic_ram && !@frozen
        return @rom if @allow_bank || !(@ram_enabled || nordic_ram)

        bank(@rom_banks, @bank & ~0x03)
      end

      def install_chips(chips)
        @rom_banks = banks_from(chips).first
        @ram_data = Array.new(4) { Array.new(BANK_SIZE, 0) }
        @through = @ram_data.map { |data| RAMBank.new(data) }
        @isolated = @ram_data.map { |data| RAMBank.new(data) }
        @readers = @ram_data.map { |data| RAMReader.new(data) }
        @allow_bank = @no_freeze = @reu_mapping = @write_once = false
        reset
      end
    end
  end
end
