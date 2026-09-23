# frozen_string_literal: true

require "spec_helper"

describe Badline::Cartridge::Flash do
  subject(:flash) { described_class.new([0x5a] * 0x80000, clock: -> { now.first }) }

  let(:now) { [0] }
  let(:unlock) { [[0x555, 0xaa], [0x2aa, 0x55]] }

  def command(*writes)
    writes.each { |offset, value| flash.write(offset, value) }
  end

  def unlocked(value, offset = 0x555)
    command(*unlock, [offset, value])
  end

  def program(offset, value)
    unlocked(0xa0)
    flash.write(offset, value)
  end

  def at(cycle)
    now[0] = cycle
  end

  def erase_sector(offset)
    unlocked(0x80)
    unlocked(0x30, offset)
  end

  it "reads the array" do
    expect(flash.read(0x12345)).to eq(0x5a)
  end

  describe "autoselect" do
    before { unlocked(0x90) }

    it "reads the manufacturer at offset 0" do
      expect(flash.read(0x10000)).to eq(0x01)
    end

    it "reads the Am29F040B device code at offset 1" do
      expect(flash.read(0x10001)).to eq(0xa4)
    end

    it "reads every sector as unprotected at offset 2" do
      expect(flash.read(0x70002)).to eq(0x00)
    end

    it "stays until a reset" do
      flash.read(0)
      expect(flash.read(0)).to eq(0x01)
    end

    it "leaves on a lone $F0" do
      flash.write(0x1234, 0xf0)
      expect(flash.read(0)).to eq(0x5a)
    end

    it "leaves on the unlocked reset command" do
      unlocked(0xf0)
      expect(flash.read(0)).to eq(0x5a)
    end
  end

  it "decodes the unlock addresses from A10-A0 alone" do
    command([0x7d55, 0xaa], [0x12aa, 0x55], [0x3555, 0x90])
    expect(flash.read(1)).to eq(0xa4)
  end

  it "ignores a command with a wrong unlock cycle" do
    command([0x555, 0xaa], [0x2ab, 0x55], [0x555, 0x90])
    expect(flash.read(1)).to eq(0x5a)
  end

  describe "byte program" do
    it "clears the bits the value clears" do
      program(0x4000, 0x18)
      expect(flash.data[0x4000]).to eq(0x18)
    end

    it "programs a single byte" do
      program(0x4000, 0x18)
      expect(flash.data[0x4001]).to eq(0x5a)
    end

    it "needs the unlock sequence for every byte" do
      program(0x4000, 0x18)
      flash.write(0x4001, 0x00)
      expect(flash.data[0x4001]).to eq(0x5a)
    end

    context "with the program running" do
      before { program(0x4000, 0x18) }

      it "reads the complement of the programmed bit 7 on DQ7" do
        expect(flash.read(0x4000) & 0x80).to eq(0x80)
      end

      it "toggles DQ6 on every read" do
        expect(Array.new(3) { flash.read(0x4000) & 0x40 }).to eq([0x40, 0x00, 0x40])
      end

      it "leaves the window for status reads" do
        expect(flash.array_mode?).to be(false)
      end
    end

    context "when the program time has passed" do
      before do
        program(0x4000, 0x18)
        at(described_class::PROGRAM_CYCLES)
      end

      it "reads the programmed byte" do
        expect(flash.read(0x4000)).to eq(0x18)
      end
    end

    context "when the value sets a cleared bit" do
      before { program(0x4000, 0x7a) }

      it "reports the failure on DQ5" do
        expect(flash.read(0x4000) & 0x20).to eq(0x20)
      end

      it "keeps reporting it past the program time" do
        at(1000)
        expect(flash.read(0x4000) & 0x20).to eq(0x20)
      end

      it "returns to the array on a reset" do
        flash.write(0, 0xf0)
        expect(flash.read(0x4000)).to eq(0x5a)
      end
    end
  end

  describe "sector erase" do
    before do
      erase_sector(0x12345)
    end

    it "reads DQ3 clear in the window for more sectors" do
      expect(flash.read(0x10000) & 0x08).to eq(0x00)
    end

    it "reads DQ3 set once the erase has begun" do
      at(described_class::ERASE_WINDOW_CYCLES)
      expect(flash.read(0x10000) & 0x08).to eq(0x08)
    end

    it "reads DQ7 clear while erasing" do
      at(described_class::ERASE_WINDOW_CYCLES)
      expect(flash.read(0x10000) & 0x80).to eq(0x00)
    end

    context "when the erase time has passed" do
      before { at(described_class::ERASE_WINDOW_CYCLES + described_class::SECTOR_ERASE_CYCLES) }

      it "erases the 64K sector the address falls in" do
        flash.read(0)
        expect(flash.data[0x10000, 0x10000].uniq).to eq([0xff])
      end

      it "leaves the neighbouring sectors alone" do
        flash.read(0)
        expect([flash.data[0xffff], flash.data[0x20000]]).to eq([0x5a, 0x5a])
      end
    end

    context "with a second sector inside the window" do
      before do
        at(40)
        flash.write(0x30000, 0x30)
        at(40 + described_class::ERASE_WINDOW_CYCLES + (2 * described_class::SECTOR_ERASE_CYCLES))
      end

      it "erases both, taking a sector's time for each" do
        flash.read(0)
        expect([flash.data[0x10000], flash.data[0x30000]]).to eq([0xff, 0xff])
      end
    end

    it "aborts on another command in the window" do
      flash.write(0, 0x00)
      at(5_000_000)
      expect(flash.read(0x10000)).to eq(0x5a)
    end

    context "when suspended" do
      before do
        at(500_000)
        flash.write(0, 0xb0)
      end

      it "reads the other sectors" do
        expect(flash.read(0x20000)).to eq(0x5a)
      end

      it "reads status from the sector it erases" do
        expect(flash.read(0x10000)).to eq(0x80)
      end

      it "finishes the rest of the erase after a resume" do
        flash.write(0, 0x30)
        at(500_000 + described_class::SECTOR_ERASE_CYCLES)
        expect(flash.read(0x10000)).to eq(0xff)
      end
    end
  end

  describe "chip erase" do
    before do
      unlocked(0x80)
      unlocked(0x10)
    end

    it "reads status while erasing" do
      at(described_class::CHIP_ERASE_CYCLES - 1)
      expect(flash.read(0) & 0x88).to eq(0x08)
    end

    it "erases every sector" do
      at(described_class::CHIP_ERASE_CYCLES)
      flash.read(0)
      expect(flash.data.uniq).to eq([0xff])
    end
  end

  describe "windows" do
    it "reads a bank of the array" do
      expect(flash.window(0x2000).peek(0x9000)).to eq(0x5a)
    end

    it "writes through to the chip at the bank's offset" do
      window = flash.window(0x2000)
      [[0x8555, 0xaa], [0x82aa, 0x55], [0x8555, 0xa0], [0x8001, 0x00]].each { |args| window.poke(*args) }
      expect(flash.data[0x2001]).to eq(0x00)
    end

    it "tells the cartridge when reads stop coming from the array" do
      changes = 0
      flash.on_change { changes += 1 }
      unlocked(0x90)
      expect(changes).to eq(1)
    end

    it "hands out a status window in autoselect" do
      unlocked(0x90)
      expect(flash.window(0).peek(0xe001)).to eq(0xa4)
    end
  end
end
