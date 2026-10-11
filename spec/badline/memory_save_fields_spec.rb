# frozen_string_literal: true

require "spec_helper"
require_relative "../support/keyed_oracle"

# The memories', the RAM expansions' and the buses' keyed fields against their positional
# save_state, which restores exactly.
describe Badline::Memory, "#save_fields" do
  include KeyedOracle

  def read(out) = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TEST"))

  context "with a +60K bank switched in" do
    let(:machine) { Badline::C64.new(ram_expansion: :plus60k) }
    let(:fresh) { Badline::C64.new(ram_expansion: :plus60k) }

    before do
      machine.address_bus.poke(0xd100, 0x80)
      machine.address_bus.poke(0x4321, 0x5a)
      keyed_round_trip(machine.address_bus.ram_expansion, fresh.address_bus.ram_expansion)
    end

    it "restores the register and bank 1" do
      expect(positional(fresh.address_bus.ram_expansion)).to eq(positional(machine.address_bus.ram_expansion))
    end
  end

  context "with +256K banks picked and locked" do
    let(:machine) { Badline::C64.new(ram_expansion: :plus256k) }
    let(:fresh) { Badline::C64.new(ram_expansion: :plus256k) }

    before do
      machine.address_bus.poke(0xd100, 0x9e)
      machine.address_bus.poke(0x2000, 0xa5)
      machine.address_bus.poke(0xc000, 0x3c)
      keyed_round_trip(machine.address_bus.ram_expansion, fresh.address_bus.ram_expansion)
    end

    it "restores the banks, the lock and banks 1 to 3" do
      expect(positional(fresh.address_bus.ram_expansion)).to eq(positional(machine.address_bus.ram_expansion))
    end
  end

  context "with the RAM and colour RAM written" do
    let(:machine) { Badline::C64.new.tap { |c64| c64.run_cycles(3_000) } }
    let(:fresh) { Badline::C64.new }

    before do
      machine.address_bus.poke(0xd800, 0x0e)
      out = Badline::Snapshot::Keyed::Writer.new
      machine.address_bus.ram.save_fields(out, "ram")
      machine.address_bus.color_ram.save_fields(out, "bank0")
      input = read(out)
      fresh.address_bus.ram.load_fields(input, "ram")
      fresh.address_bus.color_ram.load_fields(input, "bank0")
    end

    it "restores every byte" do
      expect([positional(fresh.address_bus.ram), positional(fresh.address_bus.color_ram)])
        .to eq([positional(machine.address_bus.ram), positional(machine.address_bus.color_ram)])
    end
  end

  context "with a VIC-20 cartridge's ROM chips" do
    let(:machine) { Badline::Vic20.new.tap { |vic20| vic20.run_cycles(5_000) } }
    let(:fresh) { Badline::Vic20.new }

    before do
      machine.bus.map_rom(0xa000, Array.new(0x2000) { |i| i & 0xff })
      machine.bus.map_rom(0x6000, Array.new(0x1000, 0x42))
      out = Badline::Snapshot::Keyed::Writer.new
      machine.bus.ram.poke(0x1234, 0x99)
      machine.bus.ram.save_fields(out, "ram")
      machine.bus.color_ram.save_fields(out, "bank0")
      machine.bus.save_fields(out, "bus.")
      machine.bus.save_rom_fields(out)
      input = read(out)
      fresh.bus.ram.load_fields(input, "ram")
      fresh.bus.color_ram.load_fields(input, "bank0")
      fresh.bus.load_fields(input, "bus.")
      fresh.bus.load_rom_fields(input)
      fresh.bus.restored!
    end

    it "restores the RAM, the colour RAM, the data lines and the ROM chips" do
      expect(positional(fresh.bus)).to eq(positional(machine.bus))
    end

    it "maps the ROM chips' pages" do
      expect(fresh.bus.peek(0xa0ff)).to eq(0xff)
    end
  end

  context "with the C128's last bus access" do
    let(:machine) { Badline::C128.new.tap { |c128| c128.run_cycles(5_000) } }
    let(:fresh) { Badline::C128.new }

    before do
      keyed_round_trip(machine.address_bus, fresh.address_bus, "bus.")
    end

    it "restores the address and the data" do
      expect([fresh.address_bus.address, fresh.address_bus.data])
        .to eq([machine.address_bus.address, machine.address_bus.data])
    end
  end
end
