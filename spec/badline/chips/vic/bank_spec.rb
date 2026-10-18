# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/cartridge_builder"

describe Badline::Chips::VIC::Bank do
  subject(:vic_bank) { bus.vic.vic_bank }

  let(:bus) { Badline::C64::Bus.new }

  before do
    bus.cia2.poke(0xdd00, 0x03)
    bus.cia2.poke(0xdd02, 0x03)
  end

  describe ".start" do
    subject { vic_bank.start }

    it { is_expected.to eq(0x0000) }

    context "when CIA2 register is 00" do
      before { bus.cia2.poke(0xdd00, 0b00) }

      it { is_expected.to eq(0xc000) }
    end

    context "when CIA2 register is 01" do
      before { bus.cia2.poke(0xdd00, 0b01) }

      it { is_expected.to eq(0x8000) }
    end

    context "when CIA2 register is 10" do
      before { bus.cia2.poke(0xdd00, 0b10) }

      it { is_expected.to eq(0x4000) }
    end
  end

  # Pinned by fetchsplit on the 8565.
  describe "#sample_lines" do
    let(:cia2) { bus.cia2 }

    before do
      cia2.poke(0xdd00, 0b10)
      vic_bank.sample_lines
    end

    def swap(register, value)
      cia2.poke(register, value)
      vic_bank.sample_lines
      vic_bank.start
    end

    it "shows bank 3 for the cycle after a write swaps the bank lines" do
      expect(swap(0xdd00, 0b01)).to eq(0xc000)
    end

    it "shows the new bank from the cycle after that" do
      swap(0xdd00, 0b01)
      vic_bank.sample_lines
      expect(vic_bank.start).to eq(0x8000)
    end

    it "shows the new bank at once when only one line moves" do
      expect(swap(0xdd00, 0b11)).to eq(0x0000)
    end

    it "shows the new bank at once when both lines move the same way" do
      cia2.poke(0xdd00, 0b00)
      vic_bank.sample_lines
      expect(swap(0xdd00, 0b11)).to eq(0x0000)
    end

    it "shows the new bank at once when the DDR swaps the lines" do
      cia2.poke(0xdd00, 0b00)
      cia2.poke(0xdd02, 0b01)
      vic_bank.sample_lines
      expect(swap(0xdd02, 0b10)).to eq(0x8000)
    end
  end

  describe "#peek_color" do
    subject { vic_bank.peek_color(3) }

    before do
      bus.color_ram.poke(0xd803, 0x0b)
    end

    it { is_expected.to eq(0x0b) }
  end

  context "with a cartridge in Ultimax mode for the CPU's half of the cycle only" do
    include CartridgeBuilder

    before do
      cartridge = build_cartridge(36, (0..3).map { |n| chip(bank: n, fill: 0x10 * (n + 1)) })
      bus.attach_cartridge(cartridge)
      bus.poke(0xde00, 0x03)
    end

    it "reads the character ROM in the first half" do
      expect(vic_bank.peek(0x1000)).to eq(bus.character_rom.peek(0xd000))
    end

    it "reads ROMH in the second half" do
      expect(vic_bank.peek_phi2(0x3000)).to eq(0x10)
    end

    it "reads RAM again once the cartridge leaves Ultimax mode" do
      bus.poke(0xde00, 0x00)
      expect(vic_bank.peek_phi2(0x3000)).to eq(bus.ram.peek(0x3000))
    end
  end

  context "with memory a machine places at other bases" do
    subject(:vic_bank) { Badline::Chips::VIC.new.vic_bank }

    let(:ram) { Badline::Memory.new(Array.new(2**17) { |addr| addr >> 12 }, length: 2**17) }
    let(:rom) { Badline::ROM.new(Array.new(0x2000) { |addr| addr >> 8 }, length: 0x2000) }
    let(:color_ram) { Badline::C64::ColorMemory.new(Badline::Chips::VIC.new, start: 0, length: 0x800) }

    it "reads a sprite's s-accesses as any other read off the video bus" do
      vic_bank.map(ram, base: 0x10000)
      expect(vic_bank.peek_sprite(0x2000)).to eq(vic_bank.peek(0x2000))
    end

    it "reads RAM from the base of the VIC's 64K" do
      vic_bank.map(ram, base: 0x10000)
      expect(vic_bank.peek(0x2000)).to eq(0x12)
    end

    it "reads the character ROM from its base" do
      vic_bank.map_character_rom(rom, base: 0x0000)
      expect(vic_bank.peek(0x1100)).to eq(0x11)
    end

    it "reads RAM under the character ROM when the shadow is off" do
      vic_bank.map(ram)
      vic_bank.map_character_rom(rom, shadow: false)
      expect(vic_bank.peek(0x1000)).to eq(0x01)
    end

    it "reads colour RAM from its base" do
      color_ram.poke(0x403, 0x0b)
      vic_bank.connect(cia2: Badline::Chips::CIA.new(start: 0xdd00), color_ram:, color_base: 0x400)
      expect(vic_bank.peek_color(3)).to eq(0x0b)
    end
  end

  # The P500's FPLA equations, sheet 15 of its schematic.
  describe "#map_video_bus" do
    subject(:vic_bank) { Badline::Chips::VIC.new.vic_bank }

    let(:dram) { Badline::Memory.new(Array.new(2**16) { |addr| (addr >> 8) & 0xff }) }
    let(:matrix) { Badline::Memory.new(Array.new(0x400) { |addr| addr & 0xff }, length: 0x400, start: 0xd000) }
    let(:color_ram) { Badline::C64::ColorMemory.new(Badline::Chips::VIC.new, start: 0xd400) }
    let(:rom) { Badline::ROM.new(Array.new(0x1000) { |addr| (addr >> 4) & 0xff }, length: 0x1000, start: 0xc000) }

    before do
      vic_bank.map_character_rom(rom, base: 0xc000)
      vic_bank.map_video_bus(dram, matrix, color_ram, 0xd400)
    end

    def read(statvid, dotsel, bank, offset)
      vic_bank.video_bus_lines(statvid, dotsel, bank)
      [vic_bank.peek(offset), vic_bank.peek_phi2(offset)]
    end

    it "reads the character ROM in phi1 with VICDOTSEL high, from VA0-VA11" do
      expect(read(false, true, 0, 0x3120).first).to eq(0x12)
    end

    it "reads the static matrix in phi2 with STATVID and VA12 high, from VA0-VA9" do
      expect(read(true, false, 0, 0x1f05).last).to eq(0x05)
    end

    it "reads 0 in phi2 with STATVID high and VA12 low" do
      expect(read(true, true, 2, 0x0f05).last).to eq(0)
    end

    it "reads the DRAM with both low, in the 16K bank VA14 and VA15 pick" do
      expect(read(false, false, 2, 0x1234)).to eq([0x92, 0x92])
    end

    # The first and third s-accesses of a sprite fall in phi2: with STATVID
    # high they read the static matrix, as xcbm5x0 doesn't, and with it low
    # the DRAM, as it does.
    it "reads a sprite's phi2 bytes as the other phi2 reads" do
      vic_bank.video_bus_lines(true, true, 0)
      expect([vic_bank.peek_sprite(0x1f05), vic_bank.peek_sprite(0x0f05)]).to eq([0x05, 0])
    end

    it "reads a sprite's phi2 bytes from the DRAM with STATVID low" do
      vic_bank.video_bus_lines(false, true, 1)
      expect(vic_bank.peek_sprite(0x1234)).to eq(0x52)
    end

    it "reads the colour nibbles from the colour RAM" do
      color_ram.poke(0xd403, 0x0b)
      expect(vic_bank.peek_color(3)).to eq(0x0b)
    end
  end
end
