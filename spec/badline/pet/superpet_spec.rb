# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/pet_boot"

# The board's latches, after Levak's PET-Interfaces.txt, André Fachat's
# SuperPET page and Commodore's 324037 schematic, sheets 1 and 2.
describe Badline::PET::SuperPET do
  subject(:superpet) { described_class.new }

  # The byte at $9000 of +bank+, picked through the bank latch.
  def bank_byte(bank)
    superpet.poke(0xeffc, bank)
    superpet.peek(0x9000)
  end

  def fill_banks
    16.times do |bank|
      superpet.poke(0xeffc, bank)
      superpet.poke(0x9000, 0x40 + bank)
    end
  end

  # Opens the system latch through bit 7 of the bank latch and writes it.
  def write_system_latch(value)
    superpet.poke(0xeffc, 0x80)
    superpet.poke(0xeff8, value)
  end

  # PIA 1's port A, as the diagnostic sense line leaves PA7.
  def diagnostic_sense
    superpet.pia1.poke(0xe811, 0x04)
    superpet.pia1.peek(0xe810) & 0x80
  end

  # What a read of +addr+ finds just after the bus carried +last+.
  def read_after(last, addr)
    superpet.poke(0x0000, last)
    superpet.peek(addr)
  end

  it "is an 8032 with the 901640-01 character ROM" do
    profile = superpet.model
    expect([profile.basic, profile.kernal, profile.video, profile.characters])
      .to eq(["pet/basic4.rom", "pet/kernal4.rom", :crtc80, "pet/characters-superpet.rom"])
  end

  it "names its 96K for the pause menu" do
    expect(superpet.model_label).to eq("SUPERPET, 96K RAM, 50 HZ")
  end

  it "is built as its own class, not as a PET" do
    expect { Badline::PET.new(model: "superpet") }.to raise_error(ArgumentError, /SuperPET/)
  end

  it "takes no RAM size of its own" do
    expect { described_class.new(ram_kb: 16) }.to raise_error(ArgumentError)
  end

  describe "the bank window at $9000" do
    it "shows 16 banks of 4K, one at a time" do
      fill_banks
      expect(Array.new(16) { |bank| bank_byte(bank) }).to eq(Array.new(16) { |bank| 0x40 + bank })
    end

    it "picks the bank with bits 0-3 alone" do
      fill_banks
      expect([bank_byte(0x13), bank_byte(0x85)]).to eq([0x43, 0x45])
    end

    it "takes the bank latch at $EFFD too" do
      fill_banks
      superpet.poke(0xeffd, 7)
      expect(superpet.peek(0x9000)).to eq(0x47)
    end

    it "spans $9000-$9FFF of the bank" do
      superpet.poke(0xeffc, 2)
      superpet.poke(0x9fff, 0x5a)
      expect(superpet.board.cells[0x2fff]).to eq(0x5a)
    end

    it "shows bank 0 after the RES line" do
      fill_banks
      superpet.poke(0xeffc, 9)
      superpet.reset!
      expect(superpet.peek(0x9000)).to eq(0x40)
    end

    it "leaves the 8032's RAM, BASIC and KERNAL where they are" do
      superpet.poke(0x7fff, 0x12)
      expect([superpet.peek(0x7fff), superpet.peek(0xb000), superpet.peek(0xfffc)])
        .to eq([0x12, Badline::ROM.read("pet/basic4.rom").first, 0x16])
    end
  end

  describe "the RAM or ROM select at $EFFE" do
    it "puts the empty ROM socket at $9000 with bit 0 set" do
      superpet.poke(0xeffe, 0x01)
      expect(read_after(0x93, 0x9000)).to eq(0x93)
    end

    it "lets writes to the socket go nowhere and brings the RAM back with bit 0 clear" do
      superpet.poke(0x9000, 0x21)
      superpet.poke(0xefff, 0x01)
      superpet.poke(0x9000, 0x22)
      superpet.poke(0xeffe, 0x00)
      expect(superpet.peek(0x9000)).to eq(0x21)
    end

    it "is cleared by the RES line" do
      superpet.poke(0x9000, 0x31)
      superpet.poke(0xeffe, 0x01)
      superpet.reset!
      expect(superpet.peek(0x9000)).to eq(0x31)
    end
  end

  describe "the system latch at $EFF8" do
    it "ignores writes while bit 7 of the bank latch is clear" do
      superpet.poke(0xeff8, 0x08)
      expect(superpet.board.system_latch).to eq(0)
    end

    it "takes them at $EFF8-$EFFB while it is set" do
      superpet.poke(0xeffc, 0x80)
      superpet.poke(0xeffb, 0x0a)
      expect(superpet.board.system_latch).to eq(0x0a)
    end

    it "pulls the diagnostic sense on PIA 1's PA7 low with bit 3" do
      write_system_latch(0x08)
      expect(diagnostic_sense).to eq(0)
    end

    it "leaves the diagnostic sense high without it" do
      write_system_latch(0x00)
      expect(diagnostic_sense).to eq(0x80)
    end

    it "is cleared by the RES line" do
      write_system_latch(0x0b)
      superpet.reset!
      expect([superpet.board.system_latch, superpet.board.bank_latch]).to eq([0, 0])
    end
  end

  describe "the bank RAM's write protect" do
    it "lets writes through with SW1 at R/W" do
      superpet.poke(0x9000, 0x11)
      expect(superpet.peek(0x9000)).to eq(0x11)
    end

    context "with SW1 at READ" do
      subject(:superpet) { described_class.new(bank_ram: "read") }

      it "lets writes go nowhere" do
        superpet.poke(0x9000, 0x11)
        expect(superpet.peek(0x9000)).to eq(0x00)
      end
    end

    context "with SW1 at PROG" do
      subject(:superpet) { described_class.new(bank_ram: "prog") }

      it "starts read only, the system latch cleared" do
        superpet.poke(0x9000, 0x11)
        expect(superpet.peek(0x9000)).to eq(0x00)
      end

      it "lets writes through with bit 1 of the system latch set" do
        write_system_latch(0x02)
        superpet.poke(0x9000, 0x11)
        expect(superpet.peek(0x9000)).to eq(0x11)
      end
    end

    it "refuses a switch position the board doesn't have" do
      expect { described_class.new(bank_ram: "on") }.to raise_error(ArgumentError, /on/)
    end
  end

  describe "the CPU switch" do
    it "is at 6502 unless set" do
      expect(superpet.board.cpu_switch).to eq("6502")
    end

    it "refuses a position the board doesn't have" do
      expect { described_class.new(cpu: "z80") }.to raise_error(ArgumentError, /z80/)
    end
  end

  describe "the I/O page at $EF00" do
    it "reads the 6702 at $EFE0-$EFE3" do
      expect(Array.new(4) { |offset| superpet.peek(0xefe0 + offset) }).to eq([0xd6] * 4)
    end

    it "reads the ACIA at $EFF0-$EFF3, its status with DCD and DSR high and the transmitter empty" do
      expect(Array.new(4) { |offset| superpet.peek(0xeff0 + offset) }).to eq([0x00, 0x70, 0x00, 0x00])
    end

    it "reads $FF where nothing answers below $EFF0" do
      expect([read_after(0x00, 0xef00), read_after(0x00, 0xefdf), read_after(0x00, 0xefe4)]).to eq([0xff] * 3)
    end

    it "reads the last byte on the bus from the write-only latches" do
      expect([read_after(0x5c, 0xeff4), read_after(0x5d, 0xeff8), read_after(0x5e, 0xefff)]).to eq([0x5c, 0x5d, 0x5e])
    end

    it "leaves $E900-$EEFF empty" do
      expect(read_after(0x37, 0xee00)).to eq(0x37)
    end
  end

  it "wires the ACIA's IRQ to the CPU's" do
    superpet.poke(0xeff3, 0x1f)
    superpet.poke(0xeff2, 0x05)
    superpet.run_cycles(1_000)
    expect([superpet.acia.irq?, superpet.cpu.irq]).to eq([true, true])
  end

  it "resets the ACIA with the RES line" do
    superpet.poke(0xeff2, 0x05)
    superpet.reset!
    expect(superpet.peek(0xeff2)).to eq(0x00)
  end

  it "clears the bank RAM at power-on" do
    superpet.poke(0x9000, 0x77)
    superpet.power_cycle!
    expect(superpet.board.cells.uniq).to eq([0])
  end

  describe "booted in 6502 mode", :slow do
    include PETBoot

    # The booted machine, and its screen after BASIC types +text+.
    def typed(text)
      TakenOnce.fetch([:superpet_typed, text]) do
        pet = TakenOnce.fetch(:superpet_booted) do
          described_class.new.tap { |booted| booted.run_cycles(booted.init_threshold) }
        end
        pet.type_text(text)
        pet.run_cycles(400_000)
        screen_of(pet, 12)
      end
    end

    it "shows the 8032's banner and BYTES FREE, then READY, as xpet does" do
      expect(typed("")[0, 5]).to eq(["*** COMMODORE BASIC 4.0 ***", "", " 31743 BYTES FREE", "", "READY."])
    end

    it "reaches the bank latch and the bank RAM from BASIC" do
      lines = typed("b=61436:pokeb,5:poke36864,77:pokeb,0:?peek(36864):pokeb,5:?peek(36864)\r")
      expect(lines[6, 2]).to eq([" 0", " 77"])
    end
  end
end
