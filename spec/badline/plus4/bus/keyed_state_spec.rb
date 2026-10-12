# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

# The bus's keyed fields and the cartridges' ROMs by slot, loaded into a
# machine at power-on, which maps its banks from them as the saved one
# has them mapped.
describe Badline::Plus4::Bus::KeyedState do
  let(:machine) { Badline::Plus4.new }
  let(:target) { Badline::Plus4.new }
  let(:cartridge) do
    [Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 1, address: 0x8000, data: [0xc2] * 0x2000),
     Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0xc000, data: [0xc1] * 0x4000)]
  end

  # What the CPU and the TED see through the banks, and the bus's own
  # latches.
  def seen(plus4)
    bus = plus4.bus
    latches = [bus.low_bank, bus.high_bank, bus.rom_selected, bus.data, plus4.ted.peek(0xff13) & 0x01]
    latches + Array.new(0x80) { |page| bus.peek(0x8000 + (page << 8)) } +
      Array.new(0x80) { |page| bus.ted_pattern_fetch(0x8000 + (page << 8), true) }
  end

  def slots(plus4) = plus4.bus.save_slot_fields(Badline::Snapshot::Keyed::Writer.new).to_s

  def round_trip(plus4, fresh)
    out = Badline::Snapshot::Keyed::Writer.new
    plus4.bus.save_fields(out, "bus.")
    plus4.bus.save_slot_fields(out)
    input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TEST"))
    fresh.bus.load_fields(input, "bus.")
    fresh.bus.load_slot_fields(input)
    fresh.bus.restored!
  end

  before do
    machine.bus.attach_cartridge(cartridge)
    machine.bus.poke(0xfdd8, 0)
    machine.bus.poke(0x0002, 0x99)
  end

  it "maps the cartridges, the banks and ROM as the saved bus has them" do
    round_trip(machine, target)
    expect(seen(target)).to eq(seen(machine))
  end

  it "maps RAM where the saved bus has it selected" do
    machine.bus.poke(0xff3f, 0)
    round_trip(machine, target)
    expect(seen(target)).to eq(seen(machine))
  end

  it "carries each slot's ROM over" do
    round_trip(machine, target)
    expect(slots(target)).to eq(slots(machine))
  end

  it "takes cartridges out of the slots the module holds nothing for" do
    round_trip(target, machine)
    expect(machine.bus.cartridge?).to be(false)
  end
end
