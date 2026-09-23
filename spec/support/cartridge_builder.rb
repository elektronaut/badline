# frozen_string_literal: true

# Builds cartridges from in-memory CHIP packets. Each chip is filled with a
# single marker byte, so a read tells which bank answered.
module CartridgeBuilder
  CRT = Struct.new(:hardware_type, :subtype, :exrom, :game, :name, :chips, keyword_init: true)

  def chip(bank:, fill:, address: 0x8000, size: 0x2000)
    Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank:, address:, data: [fill] * size)
  end

  # A 16K chip at $8000: ROML reads `fill`, ROMH reads `fill + 1`.
  def chip16k(bank:, fill:)
    Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank:, address: 0x8000,
                                        data: ([fill] * 0x2000) + ([fill + 1] * 0x2000))
  end

  def build_cartridge(type, chips, exrom: 0, game: 1, subtype: 0)
    Badline::Cartridge.from_crt(CRT.new(hardware_type: type, subtype:, exrom:, game:, name: "TEST", chips:))
  end

  def attached_bus(cartridge)
    Badline::AddressBus.new.tap { |bus| bus.attach_cartridge(cartridge) }
  end
end
