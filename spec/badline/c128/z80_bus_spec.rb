# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::Z80Bus do
  subject(:z80_bus) do
    described_class.new(bus).tap { |z80_bus| z80_bus.machine = machine }
  end

  let(:bus) { Badline::C128::Bus.new(Badline::C128::Model::C128, mode:) }
  let(:machine) { instance_double(Badline::C128, z80_catch_up: nil) }
  let(:mode) { :c128 }

  def map_cr(value)
    bus.mmu.poke_configuration(0xff00, value)
  end

  context "with CR's RAM bank 0" do
    before { map_cr(0x3e) }

    it "reads the Z80 BIOS at $0000-$0FFF" do
      expect(z80_bus.fetch(0x0000)).to eq(Badline::ROM.read("c128/kernal.rom")[0x1000])
    end

    # Pinned by tstouti2 and c128modez80-25.
    it "writes $0000-$0FFF into the RAM at $D000-$DFFF" do
      z80_bus.write(0x0f00, 0x5a)
      expect(bus.ram.peek(0xdf00)).to eq(0x5a)
    end

    # Pinned by c128modez80-16.
    it "takes an IN at $0000-$0FFF from the RAM at $D000-$DFFF" do
      bus.ram.poke(0xd48d, 0x66)
      expect(z80_bus.input(0x048d)).to eq(0x66)
    end

    it "brings the chips up to an IN or OUT first" do
      z80_bus.output(0xd020, 0x01)
      expect(machine).to have_received(:z80_catch_up)
    end
  end

  # Pinned by c128modez80-18 and -20.
  it "reads RAM at $0000-$0FFF with CR's RAM bank 1" do
    map_cr(0x7e)
    bus.ram.poke(0x10f00, 0xa1)
    expect(z80_bus.read(0x0f00)).to eq(0xa1)
  end

  # Pinned by tstz80bk.
  it "leaves out the BIOS with CR's bank bits at 2, though that is bank 0 on a 128K machine" do
    map_cr(0xbf)
    bus.ram.poke(0x0f00, 0xb1)
    expect(z80_bus.read(0x0f00)).to eq(0xb1)
  end

  # Pinned by c128modez80-01.
  it "reads RAM at $D000-$DFFF, where the 8502 sees I/O" do
    map_cr(0x3e)
    bus.ram.poke(0xd020, 0x77)
    expect(z80_bus.read(0xd020)).to eq(0x77)
  end

  # Pinned by c128modez80-05, whose OUT to $D7FF reports with I/O off.
  it "reaches the VIC with an OUT while I/O is mapped out" do
    map_cr(0x3f)
    z80_bus.output(0xd020, 0x06)
    expect(bus.vic.peek(0xd020) & 0x0f).to eq(0x06)
  end

  # Pinned by c128modez80-10.
  it "reads memory with an IN at $D500 while I/O is mapped out" do
    map_cr(0x3f)
    bus.ram.poke(0xd506, 0x99)
    expect(z80_bus.input(0xd506)).to eq(0x99)
  end

  # Pinned by tstz80bk.
  it "writes the MMU with an OUT at $D500 while I/O is mapped out" do
    map_cr(0x3f)
    z80_bus.output(0xd506, 0x0b)
    expect(bus.mmu.registers[Badline::C128::MMU::RCR]).to eq(0x0b)
  end

  # Pinned by c128modez80-02 to -05.
  it "shows the colour RAM at $1000-$13FF while I/O is mapped in" do
    map_cr(0x3e)
    z80_bus.write(0x1005, 0x0c)
    expect(z80_bus.input(0xd805) & 0x0f).to eq(0x0c)
  end

  context "when in C64 mode" do
    let(:mode) { :c64 }

    # Pinned by c64modez80-01.
    it "reaches the VIC through memory, as the PLA decodes it" do
      z80_bus.write(0xd020, 0x05)
      expect(bus.vic.peek(0xd020) & 0x0f).to eq(0x05)
    end
  end
end
