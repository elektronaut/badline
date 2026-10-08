# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::MMU do
  subject(:mmu) { described_class.new }

  it "powers on in C64 mode with the 8502 selected" do
    expect([mmu.mode, mmu.registers[5]]).to eq([:c64, 0x41])
  end

  it "reads its version as two banks of version 0" do
    expect(mmu.registers[11]).to eq(0x20)
  end

  it "shows the VIC bank 0" do
    expect(mmu.vic_bank).to eq(0)
  end

  it "comes back to C64 mode on a reset" do
    mmu.registers[5] = 0
    mmu.reset!
    expect(mmu.mode).to eq(:c64)
  end

  context "when built for C128 mode" do
    subject(:mmu) { described_class.new(:c128) }

    let(:changes) { [] }

    before { mmu.on_change { changes << mmu.cr } }

    it "resets into C128 mode with the 8502 selected" do
      expect([mmu.mode, mmu.peek(0xd505) & 0x41]).to eq([:c128, 0x01])
    end

    it "comes back to C128 mode on a reset" do
      mmu.poke(0xd505, 0xf7)
      mmu.reset!
      expect(mmu.mode).to eq(:c128)
    end

    it "goes to C64 mode on MCR bit 6" do
      mmu.poke(0xd505, 0xf7)
      expect(mmu.mode).to eq(:c64)
    end

    it "reads the 40/80 key up in MCR bit 7" do
      expect(mmu.peek(0xd505) & 0x80).to eq(0x80)
    end

    it "reads the 40/80 key down as MCR bit 7 low" do
      mmu.display_key = true
      expect(mmu.peek(0xd505) & 0x80).to eq(0)
    end

    it "reads the cartridge's GAME and EXROM in MCR bits 4 and 5" do
      mmu.game = 0
      expect(mmu.peek(0xd505) & 0x30).to eq(0x20)
    end

    it "reads the version register at $D50B" do
      expect(mmu.peek(0xd50b)).to eq(0x20)
    end

    it "reads $FF above its registers, which don't mirror" do
      mmu.poke(0xd5f9, 0x01)
      expect([mmu.peek(0xd50c), mmu.peek(0xd5f9), mmu.p1_page]).to eq([0xff, 0xff, 0x01])
    end

    it "reads CR at $FF00 as at $D500" do
      mmu.poke_configuration(0xff00, 0x3e)
      expect(mmu.peek(0xd500)).to eq(0x3e)
    end

    it "copies a PCR into CR on a write to its LCR" do
      mmu.poke(0xd503, 0x7f)
      mmu.poke_configuration(0xff03, 0x00)
      expect(mmu.cr).to eq(0x7f)
    end

    it "reads a PCR at its LCR" do
      mmu.poke(0xd502, 0x55)
      expect(mmu.peek_configuration(0xff02)).to eq(0x55)
    end

    it "tells the bus when CR changes" do
      mmu.poke(0xd500, 0x3f)
      expect(changes).to eq([0x3f])
    end

    it "holds a P0H write until P0L is written" do
      mmu.poke(0xd508, 0x01)
      before = mmu.p0_bank
      mmu.poke(0xd507, 0x30)
      expect([before, mmu.p0_bank, mmu.p0_page]).to eq([0, 1, 0x30])
    end

    it "holds a P1H write until P1L is written" do
      mmu.poke(0xd50a, 0x01)
      before = mmu.p1_bank
      mmu.poke(0xd509, 0x30)
      expect([before, mmu.p1_bank]).to eq([0, 1])
    end

    it "reads P0H's high nibble as 1s" do
      mmu.poke(0xd508, 0x11)
      mmu.poke(0xd507, 0x01)
      expect(mmu.peek(0xd508)).to eq(0xf1)
    end

    it "picks the CPU's RAM bank with CR bit 6" do
      mmu.poke(0xd500, 0x7f)
      expect(mmu.cpu_bank).to eq(1)
    end

    it "picks the VIC's RAM bank with RCR bit 6" do
      mmu.poke(0xd506, 0x40)
      expect(mmu.vic_bank).to eq(1)
    end

    it "keeps 16K common RAM at the bottom on RCR $07" do
      mmu.poke(0xd506, 0x07)
      expect([mmu.common_low_pages, mmu.common_high_start]).to eq([64, 256])
    end

    it "keeps 1K common RAM at the top on RCR $08" do
      mmu.poke(0xd506, 0x08)
      expect([mmu.common_low_pages, mmu.common_high_start]).to eq([0, 252])
    end
  end
end
