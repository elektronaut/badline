# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::VDC do
  subject(:vdc) { described_class.new }

  def write_register(reg, value)
    vdc.poke(0xd600, reg)
    vdc.poke(0xd601, value)
  end

  def read_register(reg)
    vdc.poke(0xd600, reg)
    vdc.peek(0xd601)
  end

  def point_at(address)
    write_register(18, address >> 8)
    write_register(19, address & 0xff)
  end

  def ready? = vdc.peek(0xd600).anybits?(0x80)

  def run(cycles)
    cycles.times { vdc.cycle! }
  end

  describe "its status" do
    it "reads ready with the 8563's version" do
      expect(vdc.peek(0xd600) & 0x87).to eq(0x81)
    end

    it "reads the 8568's version" do
      expect(described_class.new(model: :mos8568, ram_kb: 64).peek(0xd600) & 0x07).to eq(2)
    end

    it "reads the vertical blank outside the displayed rows" do
      expect(vdc.peek(0xd600)).to eq(0xa1)
    end

    it "reads no vertical blank in a displayed row" do
      write_register(6, 25)
      expect(vdc.peek(0xd600)).to eq(0x81)
    end
  end

  it "mirrors its two registers through the page" do
    vdc.poke(0xd6f0, 12)
    vdc.poke(0xd6f1, 0x34)
    expect(read_register(12)).to eq(0x34)
  end

  it "stores 37 registers" do
    write_register(36, 0x0f)
    expect(read_register(36)).to eq(0x0f)
  end

  it "reads a register past the last as $FF" do
    expect(read_register(37)).to eq(0xff)
  end

  it "stores the 8568's 38th register" do
    vdc = described_class.new(model: :mos8568, ram_kb: 64)
    vdc.poke(0xd600, 37)
    vdc.poke(0xd601, 0x03)
    expect(vdc.peek(0xd601)).to eq(0x03)
  end

  describe "its RAM, through R18, R19 and R31" do
    before do
      point_at(0x1234)
      write_register(31, 0xaa)
      write_register(31, 0xbb)
    end

    it "writes at the update address" do
      expect(vdc.ram[0x1234, 2]).to eq([0xaa, 0xbb])
    end

    it "moves the update address on with each access" do
      expect([read_register(18), read_register(19)]).to eq([0x12, 0x36])
    end

    it "reads at the update address" do
      write_register(19, 0x34)
      expect([read_register(31), vdc.peek(0xd601)]).to eq([0xaa, 0xbb])
    end

    it "keeps 16 bits of address in 16K mode, where A14 reaches no pin" do
      point_at(0x5234)
      expect(read_register(31)).to eq(0xaa)
    end
  end

  it "has 64K when built with it" do
    expect(described_class.new(model: :mos8568, ram_kb: 64).ram.length).to eq(0x10000)
  end

  describe "a block write" do
    before do
      point_at(0x0100)
      write_register(31, 0x55)
      write_register(24, 0x00)
    end

    it "repeats the byte written over R30 more bytes" do
      write_register(30, 3)
      expect(vdc.ram[0x00ff, 6]).to eq([0, 0x55, 0x55, 0x55, 0x55, 0])
    end

    it "leaves the update address after the last byte" do
      write_register(30, 3)
      expect([read_register(18), read_register(19)]).to eq([0x01, 0x04])
    end

    it "writes 256 bytes for a word count of 0" do
      write_register(30, 0)
      expect(vdc.ram[0x0100, 258].count(0x55)).to eq(257)
    end
  end

  describe "a block copy" do
    before do
      vdc.ram[0x0200, 4] = [1, 2, 3, 4]
      point_at(0x0300)
      write_register(24, 0x80)
      write_register(32, 0x02)
      write_register(33, 0x00)
      write_register(30, 3)
    end

    it "copies R30 bytes from R32/R33 to the update address" do
      expect(vdc.ram[0x0300, 4]).to eq([1, 2, 3, 0])
    end

    it "leaves the source after the last byte" do
      expect([read_register(32), read_register(33)]).to eq([0x02, 0x03])
    end

    it "leaves the update address after the last byte" do
      expect(read_register(19)).to eq(0x03)
    end
  end

  describe "its ready bit" do
    before { write_register(22, 0x78) }

    it "drops while a write through R31 is under way" do
      write_register(31, 1)
      run(14)
      expect(ready?).to be(false)
    end

    it "comes back 30 character clocks after a write through R31" do
      write_register(31, 1)
      run(15)
      expect(ready?).to be(true)
    end

    it "drops while a write of R19 reads ahead" do
      write_register(19, 0)
      expect(ready?).to be(false)
    end

    it "takes a character clock a byte for a block write" do
      write_register(30, 0)
      run(126)
      expect(ready?).to be(false)
    end

    it "comes back after a block write's last byte" do
      write_register(30, 0)
      run(127)
      expect(ready?).to be(true)
    end

    it "takes two character clocks a byte for a block copy" do
      write_register(24, 0x80)
      write_register(30, 0)
      run(252)
      expect(ready?).to be(false)
    end

    it "counts the double-width mode's character clocks twice as long" do
      write_register(25, 0x10)
      write_register(22, 0x80)
      write_register(31, 1)
      run(15)
      expect(ready?).to be(false)
    end
  end

  describe "its raster" do
    # 64 characters of 8 dots, 8 lines a row, 39 rows: 312 lines of
    # 512 dots, 32 microseconds each.
    before do
      { 0 => 63, 4 => 38, 6 => 25, 9 => 7, 22 => 0x78 }.each { |reg, value| write_register(reg, value) }
      run(400)
    end

    it "finishes a frame every 312 lines" do
      run((312 * 512 * 985_248 / 16_000_000) + 1)
      expect(vdc.frame).to eq(1)
    end

    it "is outside the vertical blank in the first rows" do
      expect(vdc.peek(0xd600) & 0x20).to eq(0)
    end

    it "is in the vertical blank after the displayed rows" do
      run(25 * 8 * 512 * 985_248 / 16_000_000)
      expect(vdc.peek(0xd600) & 0x20).to eq(0x20)
    end
  end

  describe "its display" do
    before do
      { 0 => 63, 3 => 0x11, 4 => 38, 7 => 32, 9 => 7, 22 => 0x78 }.each { |reg, value| write_register(reg, value) }
    end

    it "doesn't paint while #render is off" do
      write_register(26, 0x0f)
      run(20_000)
      expect(vdc.display.uniq).to eq([0])
    end

    it "paints the border in the background colour while #render is on" do
      vdc.render = true
      write_register(26, 0x0f)
      run(20_000)
      expect(vdc.display).to include(0x0f)
    end
  end

  it "has the 16 RGBI colours" do
    expect(described_class::PALETTE.values_at(0, 1, 2, 12, 14, 15)).to eq([0x000000, 0x555555, 0x0000aa, 0xaaaa00,
                                                                           0xaaaaaa, 0xffffff])
  end

  it "powers on with its registers and RAM cleared" do
    write_register(12, 0x10)
    vdc.ram[5] = 1
    vdc.power_on!
    expect([vdc.registers[12], vdc.ram[5]]).to eq([0, 0])
  end
end
