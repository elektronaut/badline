# frozen_string_literal: true

module Badline
  class Cartridge
    # EasyFlash: two Am29F040B flash chips, one for ROML and one for ROMH,
    # each 64 banks of 8K, and 256 bytes of RAM at $DF00. $DE00 selects the
    # bank. $DE02 sets the memory configuration: bit 2 hands the GAME line
    # to bit 0 (otherwise the boot jumper holds it low), bit 1 pulls EXROM
    # low and bit 7 drives the LED.
    #
    # The flash takes writes in Ultimax mode, at $8000 for ROML and $E000
    # for ROMH, which is how EAPI programs and erases it. The writes stay in
    # memory; #save_crt writes the flash out as a new image.
    #
    # An image built for EasyFlash carries an EAPI, the flash driver, at $B800
    # in bank 0 of ROMH. On attach, as in VICE, the bundled Am29F040 EAPI
    # (roms/eapi) takes its place, so the image drives the flash emulated here.
    class EasyFlash < Cartridge
      BANKS = 64
      EAPI_OFFSET = 0x1800
      EAPI = File.binread(File.expand_path("../roms/eapi/eapi-am29f040-14", __dir__)).bytes.drop(2).freeze

      attr_reader :low_flash, :high_flash

      def clock=(clock)
        super
        [@low_flash, @high_flash].each { |flash| flash.clock = clock }
      end

      def readable_io_pages
        [0xdf]
      end

      def peek(addr)
        @io_ram[addr & 0xff]
      end

      def poke(addr, value)
        if addr >= 0xdf00
          @io_ram[addr & 0xff] = value
        elsif addr.nobits?(0x02)
          @bank = value & 0x3f
          select_bank
        else
          @control = value & 0x87
          apply_control
          changed!
        end
      end

      def led?
        @control.anybits?(0x80)
      end

      # Reset clears both registers, and leaves the flash and the RAM.
      def reset
        @bank = 0
        @control = 0
        apply_control
        select_bank
      end

      # Writes every bank that isn't blank to a CRT image at path.
      def save_crt(path)
        chips = (0...BANKS).flat_map do |number|
          [[@low_flash, 0x8000], [@high_flash, 0xa000]].filter_map do |flash, address|
            data = flash.data[number * BANK_SIZE, BANK_SIZE]
            Storage::CRTFile::Chip.new(chip_type: 2, bank: number, address:, data:) if data.any?(0..0xfe)
          end
        end
        image = Storage::CRTFile::Image.new(hardware_type: 32, subtype: 0, exrom: 1, game: 0, name:, chips:)
        Storage::CRTFile.write(path, image)
      end

      private

      def select_bank
        @roml = @low_flash.window(@bank * BANK_SIZE)
        @romh = @high_flash.window(@bank * BANK_SIZE)
        changed!
      end

      def apply_control
        game = @control.nobits?(0x04) || @control.anybits?(0x01)
        exrom = @control.anybits?(0x02)
        @game = game ? 0 : 1
        @exrom = exrom ? 0 : 1
      end

      def install_chips(chips)
        low = Array.new(BANKS * BANK_SIZE, 0xff)
        high = Array.new(BANKS * BANK_SIZE, 0xff)
        chips.each do |chip|
          offset = (chip.bank & 0x3f) * BANK_SIZE
          if chip.address >= ROMH_START
            place(high, offset, chip.data)
          else
            place(low, offset, chip.data)
            place(high, offset, chip.data[BANK_SIZE..]) if chip.data.length > BANK_SIZE
          end
        end
        install_eapi(high)
        @low_flash = Flash.new(low)
        @high_flash = Flash.new(high)
        [@low_flash, @high_flash].each { |flash| flash.on_change { select_bank } }
        @io_ram = Array.new(0x100, 0xff)
        reset
      end

      def install_eapi(high)
        return unless high[EAPI_OFFSET, 4] == "eapi".bytes

        high[EAPI_OFFSET, EAPI.length] = EAPI
      end

      def place(flash_data, offset, bytes)
        bytes = bytes.first(BANK_SIZE)
        flash_data[offset, bytes.length] = bytes
      end
    end
  end
end
