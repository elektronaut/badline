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

  # A 6809 program that opens the system latch and sets bit 0, for the
  # 6502: LDA #$80, STA $EFFC, LDA #$01, STA $EFF8, BRA *.
  def to_m6502 = [0x86, 0x80, 0xb7, 0xef, 0xfc, 0x86, 0x01, 0xb7, 0xef, 0xf8, 0x20, 0xfe]

  # A 6502 program that opens it and clears bit 0, for the 6809: LDA #$80,
  # STA $EFFC, LDA #$00, STA $EFF8, JMP *.
  def to_m6809 = [0xa9, 0x80, 0x8d, 0xfc, 0xef, 0xa9, 0x00, 0x8d, 0xf8, 0xef, 0x4c, 0x0a, 0x04]

  # The byte at +offset+ in the Waterloo ROM named.
  def waterloo(name, offset) = Badline::ROM.read("pet/superpet-#{name}.rom")[offset]

  # Puts +bytes+ at $1000, has the 6809 jump there from its next cycle on,
  # and runs 40 cycles.
  def run_on_m6809(bytes)
    bytes.each_with_index { |byte, index| superpet.poke(0x1000 + index, byte) }
    superpet.m6809.pc = 0x1000
    superpet.m6809.resume(superpet.m6809.cycles)
    superpet.run_cycles(40)
  end

  # Puts +bytes+ at $0400 and has the 6502 jump there, as run_on_m6809.
  def run_on_m6502(bytes)
    bytes.each_with_index { |byte, index| superpet.poke(0x0400 + index, byte) }
    superpet.cpu.program_counter = 0x0400
    superpet.cpu.resume(superpet.cpu.cycles)
    superpet.run_cycles(40)
  end

  # Hands the bus from the 6809 to the 6502, back, and to the 6502 again,
  # each by a program on the CPU that has it. Returns, after each, whether
  # the 6809 runs and the top bits of the PC of the CPU that does.
  def handovers
    run_on_m6809(to_m6502)
    found = [[superpet.m6809_running?, superpet.cpu.program_counter >> 13]]
    run_on_m6502(to_m6809)
    found << [superpet.m6809_running?, superpet.m6809.pc >> 8]
    run_on_m6809(to_m6502)
    found << [superpet.m6809_running?, superpet.cpu.program_counter >> 13]
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

    it "leaves the 8032's ROMs and the empty socket at $A000 to the 6502" do
      expect([read_after(0x42, 0xa000), superpet.peek(0xb000)]).to eq([0x42, Badline::ROM.read("pet/basic4.rom").first])
    end

    context "with the switch at 6809" do
      subject(:superpet) { described_class.new(cpu: "6809") }

      it "gives the 6809 the bus" do
        expect(superpet.m6809_running?).to be(true)
      end

      it "lays the Waterloo ROMs over the 8032's at $A000-$E7FF and $F000-$FFFF" do
        expect([superpet.peek(0xa000), superpet.peek(0xc000), superpet.peek(0xe000), superpet.peek(0xfffe)])
          .to eq([waterloo("a000", 0), waterloo("c000", 0), waterloo("e000-50hz", 0), 0xff])
      end

      it "leaves the PET's I/O and the board's where they are" do
        superpet.poke(0xe843, 0x5a)
        expect([superpet.peek(0xe843), superpet.peek(0xefe0)]).to eq([0x5a, 0xd6])
      end

      it "starts the 6809 from its reset vector, $FF80" do
        superpet.run_cycles(4)
        expect(superpet.m6809.pc).to eq(0xff80)
      end

      it "wires the IRQ line, the ACIA's with it, to the 6809's" do
        run_on_m6809([0x20, 0xfe])
        superpet.poke(0xeff3, 0x1f)
        superpet.poke(0xeff2, 0x05)
        superpet.run_cycles(1_000)
        expect(superpet.m6809.irq).to be(true)
      end

      it "runs its init handlers once the Waterloo menu is up" do
        expect(superpet.init_threshold).to eq(600_000)
      end

      it "starts no BASIC program off a disk" do
        expect(superpet.boots_basic?).to be(false)
      end

      it "ignores the system latch" do
        write_system_latch(0x01)
        expect(superpet.m6809_running?).to be(true)
      end

      it "keeps the bank RAM, not the socket, at $9000" do
        superpet.poke(0x9000, 0x24)
        superpet.poke(0xeffe, 0x01)
        expect(superpet.peek(0x9000)).to eq(0x24)
      end
    end

    context "with the switch at 6809 and the 60 Hz editor" do
      subject(:superpet) { described_class.new(cpu: "6809", refresh_hz: 60) }

      it "runs the 60 Hz Waterloo ROM, whose CRTC table has 33 rows a frame" do
        expect(superpet.peek(0xe0c1)).to eq(0x20)
      end
    end

    # SW2 at PROG, where the system latch's bit 0 picks the CPU.
    context "with the switch at PROG" do
      subject(:superpet) { described_class.new(cpu: "prog") }

      it "starts the 6809, the RES line having cleared the system latch" do
        expect(superpet.m6809_running?).to be(true)
      end

      # The 6502 is in the editor or the KERNAL, $E000 up, and the 6809 in
      # its reset code at $FF80, 40 cycles after each handover.
      it "hands the bus 6502 to 6809 to 6502 through the system latch, each CPU from its RESET" do
        expect(handovers).to eq([[false, 7], [true, 0xff], [false, 7]])
      end
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

  describe "booted in 6809 mode", :slow do
    let(:booted) do
      TakenOnce.fetch(:superpet_m6809) { described_class.new(cpu: "6809").tap { |pet| pet.run_cycles(600_000) } }
    end

    # The screen's first +rows+ rows, its codes as the Waterloo set's
    # ASCII.
    def ascii_rows(pet, rows)
      cells = pet.bus.screen.cells
      Array.new(rows) { |row| cells[row * 80, 80].map { |code| (code & 0x7f).chr }.join.rstrip }
    end

    it "shows the Waterloo menu, as xpet does" do
      expect(ascii_rows(booted, 12)).to eq(["Waterloo microSystems", "", "Select :", "", "  setup", "  monitor",
                                            "  apl", "  basic", "  edit", "  fortran", "  pascal", "  development"])
    end

    it "sets the CRTC's MA13, for the character ROM's ASCII and APL half" do
      expect(booted.crtc.registers[12]).to eq(0x30)
    end

    it "types into the Waterloo ROM's key ring, in ASCII, once the menu is up" do
      pet = described_class.new(cpu: "6809")
      pet.type_text("Hi\r")
      pet.run_cycles(pet.init_threshold + 1)
      expect(Array.new(3) { |offset| pet.peek(0x0130 + offset) }).to eq([0x48, 0x69, 0x0d])
    end
  end
end
