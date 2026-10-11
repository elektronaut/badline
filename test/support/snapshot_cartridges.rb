# frozen_string_literal: true

# Every cartridge mapper after a few register writes, reads, button presses
# and freezes, for bin/snapshot_check --carts: each one's keyed module
# saved, a cartridge built afresh from it with its state loaded, and saved
# again.
module SnapshotCartridges
  WRITES = [
    [[0xde00, 0x09], [0xde01, 0x09], [0xde02, 0x09], [0xdfff, 0x09]],
    [[0xde00, 0x01], [0xde80, 0x0a], [0xdf00, 0x05], [0xdfff, 0x32]],
    [[0xde00, 0x22], [0xde01, 0x02], [0xdfff, 0x13]],
    [[0xde00, 0x86], [0xdf00, 0x0c], [0xdfff, 0x80]],
    [[0xde00, 0x3f], [0xde00, 0x88], [0xdf00, 0x0b], [0xdfff, 0x4f]]
  ].freeze
  READS = [0xde05, 0xdf05, 0xde0f, 0xdfc5, 0xde80].freeze
  FLASH_PROGRAM = [[0xe555, 0xaa], [0xe2aa, 0x55], [0xe555, 0xa0], [0xe100, 0x12]].freeze

  Cartridge = Badline::C64::Cartridge

  module_function

  def chip(bank:, fill:, address: 0x8000)
    Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank:, address:, data: [fill] * 0x2000)
  end

  def banks(count, address: 0x8000) = Array.new(count) { |n| chip(bank: n, fill: 0x10 + n, address:) }

  def crt(type, chips, subtype: 0)
    image = Badline::Storage::CRTFile::Image.new(hardware_type: type, subtype:, exrom: 0, game: 1, name: "TEST",
                                                 chips:)
    Badline::Storage::CRTFile.new(bytes: Badline::Storage::CRTFile.encode(image))
  end

  def attach(cartridge)
    cartridge.clock = -> { 100 }
    cartridge.connect(ram: Badline::Memory.new, open_bus: nil)
    cartridge
  end

  def build(type, chips = banks(4) + banks(4, address: 0xa000), **) = attach(Cartridge.from_crt(crt(type, chips, **)))

  def drive(cartridge, writes, reads: [])
    writes.each { |address, value| cartridge.poke(address, value) }
    reads.each { |address| cartridge.peek(address) }
    cartridge
  end

  # The records `cartridge` saves in a keyed snapshot module (BL-CART).
  def save(cartridge) = Badline::Snapshot::Keyed.section("BL-CART") { |out| cartridge.save_fields(out) }

  # A cartridge built afresh from `cartridge`'s module, with its state
  # loaded.
  def round_trip(cartridge)
    input = Badline::Snapshot::Keyed::Reader.parse(save(cartridge))
    copy = attach(Cartridge.from_fields(input))
    copy.load_fields(input)
    copy
  end

  # Name => cartridge, for every mapper and write pattern, and the
  # subtypes, jumpers and GEO-RAM.
  def scenarios
    scenarios = {}
    Cartridge::HARDWARE_TYPES.each do |type, mapper|
      name = mapper.name.split("::").last
      WRITES.each_with_index { |writes, index| patterns(scenarios, "#{name}-#{index}", type, writes) }
      scenarios["#{name}-reset"] = build(type, banks(2)).tap(&:reset)
    end
    variants(scenarios)
  end

  def patterns(scenarios, name, type, writes)
    cartridge = build(type)
    reads = cartridge.readable_io_pages.empty? ? [] : READS
    scenarios[name] = drive(cartridge, writes, reads:)
    return unless cartridge.freezer?

    frozen = drive(build(type), writes, reads:)
    frozen.press_button
    frozen.freeze!
    scenarios["#{name}-frozen"] = frozen
    thawed = drive(build(type), writes, reads:)
    thawed.press_button
    thawed.freeze!
    thawed.release_button
    scenarios["#{name}-thawed"] = drive(thawed, writes.first(1))
  end

  def variants(scenarios)
    scenarios["RGCD-hucky"] = drive(build(57, banks(4), subtype: 1), [[0xde00, 0x05]])
    scenarios["RGCD-hucky-off"] = drive(build(57, banks(4), subtype: 1), [[0xde00, 0x0d]])
    scenarios["Comal80-grey"] = drive(build(21, subtype: 1), [[0xde00, 0x42]])
    scenarios["Comal80-grey-ultimax"] = drive(build(21, subtype: 1), [[0xde00, 0x23]])
    [[false, false], [true, false], [false, true], [true, true]].each do |flash_jumper, bank_jumper|
      cartridge = attach(Cartridge.from_crt(crt(36, banks(2)), flash_jumper:, bank_jumper:))
      scenarios["RetroReplay-jumpers-#{flash_jumper}-#{bank_jumper}"] =
        drive(cartridge, [[0xde01, 0x22], [0xde00, 0x20]])
    end
    scenarios["RetroReplay-nordic"] = drive(build(36, banks(2), subtype: 1), [[0xde00, 0x22]])
    easyflash = drive(build(32), [[0xde00, 1], [0xdf10, 0x42]])
    FLASH_PROGRAM.each { |address, value| easyflash.romh.poke(address, value) }
    scenarios["EasyFlash-programmed"] = easyflash
    scenarios["GeoRAM"] = drive(attach(Cartridge::GeoRAM.new(size: 64)), [[0xdfff, 2], [0xdffe, 5], [0xde10, 0x99]])
    scenarios
  end
end
