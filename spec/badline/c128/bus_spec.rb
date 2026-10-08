# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::Bus do
  subject(:bus) { described_class.new(Badline::C128::Model::C128) }

  it "has 128K of RAM" do
    expect(bus.ram.length).to eq(2**17)
  end

  it "powers its RAM on in the C64's pattern in both banks" do
    expect(Array.new(8) { |i| bus.ram.peek(0x10000 + i) }).to eq(Array.new(8) { |i| bus.ram.peek(i) })
  end

  it "shows bank 0 to the CPU, leaving bank 1 alone" do
    bank1 = bus.ram.peek(0x12000)
    bus.poke(0x2000, bank1 ^ 0xff)
    expect([bus.ram.peek(0x2000), bus.ram.peek(0x12000)]).to eq([bank1 ^ 0xff, bank1])
  end

  it "maps the C64's KERNAL, as the PLA does" do
    expect(bus.peek(0xfffc)).to eq(bus.kernal_rom.peek(0xfffc))
  end

  it "starts with the MMU in C64 mode" do
    expect(bus.mmu.mode).to eq(:c64)
  end

  describe "the CPU's last access" do
    it "holds the address and the byte read" do
      bus.ram.poke(0x2000, 0x42)
      bus.peek(0x2000)
      expect([bus.address, bus.data]).to eq([0x2000, 0x42])
    end

    it "holds the byte written" do
      bus.poke(0x2000, 0x99)
      expect(bus.data).to eq(0x99)
    end

    it "is an I/O access at $D000-$DFFF with I/O mapped" do
      bus.peek(0xdc00)
      expect([bus.io_access?, bus.vic_access?]).to eq([true, false])
    end

    it "is a VIC access at $D000-$D3FF" do
      bus.poke(0xd3ff, 0)
      expect(bus.vic_access?).to be(true)
    end

    it "is no I/O access with the character ROM at $D000" do
      bus.poke(0x00, 0x2f)
      bus.poke(0x01, 0x33)
      bus.peek(0xd000)
      expect(bus.io_access?).to be(false)
    end
  end

  describe "the I/O area" do
    before { bus.poke(0x01, 0x37) }

    it "puts the VIC-IIe at $D000" do
      bus.poke(0xd020, 0x05)
      expect(bus.vic.peek(0xd020) & 0x0f).to eq(0x05)
    end

    it "puts the SID at $D400" do
      bus.poke(0xd418, 0x0f)
      expect(bus.sid.register(0x18)).to eq(0x0f)
    end

    it "leaves the SID without mirrors above $D4FF" do
      bus.poke(0xd518, 0x0f)
      expect(bus.sid.register(0x18)).to eq(0)
    end

    it "leaves $D500-$D5FF open, with the MMU hidden" do
      expect(bus.peek(0xd505)).to eq(bus.vic.phi1_data)
    end

    it "puts the VDC at $D600" do
      expect(bus.peek(0xd600) & 0x87).to eq(0x81)
    end

    it "leaves $D700-$D7FF open" do
      expect(bus.peek(0xd7ff)).to eq(bus.vic.phi1_data)
    end

    it "puts the CIAs at $DC00 and $DD00" do
      bus.poke(0xdc02, 0x12)
      bus.poke(0xdd02, 0x34)
      expect([bus.cia1.peek(0xdc02), bus.cia2.peek(0xdd02)]).to eq([0x12, 0x34])
    end

    it "leaves I/O 1 and 2 open" do
      expect(bus.peek(0xde00)).to eq(bus.vic.phi1_data)
    end

    it "calls the debug register's handler on a write to $D7FF" do
      codes = []
      bus.install_debug_register { |code| codes << code }
      bus.poke(0xd7ff, 0xff)
      expect(codes).to eq([0xff])
    end

    it "pushes $D02F's K0-K2 into the keyboard's extra rows" do
      bus.poke(0xd02f, 0x05)
      expect(bus.control_ports.extra_rows).to eq(0xfd)
    end

    it "reads a key on the row K0 selects through CIA 1" do
      bus.keyboard.press(:help)
      bus.poke(0xd02f, 0xfe)
      expect(bus.peek(0xdc01)).to eq(0xfe)
    end
  end

  describe "the 8502's port" do
    it "reads P6 high while CAPS LOCK is up" do
      expect(bus.peek(0x01) & 0x40).to eq(0x40)
    end

    it "reads P6 low while CAPS LOCK is down" do
      bus.caps_lock = true
      expect(bus.peek(0x01) & 0x40).to eq(0)
    end

    it "reads P6 as the output when it drives it" do
      bus.poke(0x00, 0x40)
      bus.poke(0x01, 0x00)
      expect(bus.peek(0x01) & 0x40).to eq(0)
    end

    it "keeps the charge last driven onto bit 7" do
      bus.poke(0x00, 0x80)
      bus.poke(0x01, 0x80)
      bus.poke(0x00, 0x00)
      expect(bus.peek(0x01) & 0x80).to eq(0x80)
    end

    it "banks the KERNAL out on HIRAM low" do
      bus.poke(0x00, 0x2f)
      bus.poke(0x01, 0x35)
      expect(bus.peek(0xfffc)).to eq(bus.ram.peek(0xfffc))
    end
  end

  describe "in C128 mode" do
    subject(:bus) { described_class.new(Badline::C128::Model::C128, mode: :c128) }

    it "starts in C128 mode" do
      expect(bus.mmu.mode).to eq(:c128)
    end

    it "maps the C128 KERNAL at $E000 at reset" do
      expect(bus.peek(0xfffc)).to eq(bus.c128_kernal_rom.peek(0xfffc))
    end

    it "maps the screen editor at $C000" do
      expect(bus.peek(0xc000)).to eq(bus.editor_rom.peek(0xc000))
    end

    it "maps BASIC at $4000 and $8000" do
      expect([bus.peek(0x4000), bus.peek(0x8000)]).to eq([bus.basic_low_rom.peek(0x4000),
                                                          bus.basic_high_rom.peek(0x8000)])
    end

    it "maps the MMU at $D500" do
      expect(bus.peek(0xd50b)).to eq(0x20)
    end

    it "maps the C128 character set at $D000 with I/O off" do
      bus.poke(0xff00, 0x01)
      expect(bus.peek(0xd008)).to eq(bus.c128_character_rom.peek(0xd008))
    end

    it "maps RAM everywhere on CR $3F, but for the configuration registers" do
      bus.poke(0xff00, 0x3f)
      bus.poke(0xd020, 0x12)
      expect([bus.ram.peek(0xd020), bus.peek(0xff00)]).to eq([0x12, 0x3f])
    end

    it "writes the RAM under the ROMs" do
      bus.poke(0x4000, 0x12)
      expect(bus.ram.peek(0x4000)).to eq(0x12)
    end

    it "reads an empty function ROM socket as open bus" do
      bus.poke(0xff00, 0x04)
      expect(bus.peek(0x8000)).to eq(bus.vic.phi1_data)
    end

    it "shows the CPU bank 1 on CR bit 6" do
      bus.poke(0xff00, 0x7f)
      bus.poke(0x2000, 0x12)
      expect(bus.ram.peek(0x12000)).to eq(0x12)
    end

    it "keeps common RAM in bank 0" do
      bus.poke(0xd506, 0x04)
      bus.poke(0xff00, 0x7f)
      bus.poke(0x0200, 0x12)
      expect(bus.ram.peek(0x0200)).to eq(0x12)
    end

    it "copies a PCR into CR on a write to its LCR" do
      bus.poke(0xd501, 0x3f)
      bus.poke(0xff01, 0x00)
      expect(bus.peek(0xfffc)).to eq(bus.ram.peek(0xfffc))
    end

    describe "page relocation" do
      before do
        bus.poke(0xff00, 0x3e)
        bus.ram.poke(0x0080, 0x55)
        bus.ram.poke(0x3080, 0xaa)
        bus.poke(0xd508, 0x00)
        bus.poke(0xd507, 0x30)
      end

      it "moves page 0 to the page P0 names" do
        expect(bus.peek(0x0080)).to eq(0xaa)
      end

      it "reaches page 0 from the page P0 names" do
        expect(bus.peek(0x3080)).to eq(0x55)
      end

      it "stops reaching back once C64 mode leaves page 0 where it is" do
        bus.poke(0xd505, 0xf7)
        expect([bus.peek(0x0080), bus.peek(0x3080)]).to eq([0x55, 0x55])
      end
    end

    describe "colour RAM" do
      it "shows the CPU the bank P0 picks" do
        bus.poke(0x00, 0x03)
        bus.poke(0x01, 0x00)
        bus.poke(0xd800, 0x05)
        bus.poke(0x01, 0x01)
        expect(bus.peek(0xd800) & 0x0f).not_to eq(0x05)
      end

      it "shows the VIC the bank P1 picks" do
        bus.poke(0x00, 0x03)
        bus.poke(0x01, 0x01)
        bus.poke(0xd800, 0x05)
        bus.poke(0x01, 0x02)
        expect(bus.vic.vic_bank.peek_color(0)).to eq(0x05)
      end
    end

    it "shows the VIC the character ROM's C128 set while P2 is low" do
      bus.poke(0x00, 0x07)
      bus.poke(0x01, 0x00)
      expect(bus.vic.vic_bank.peek(0x1008)).to eq(bus.c128_character_rom.peek(0xd008))
    end

    it "shows the VIC the RAM bank RCR picks" do
      bus.ram.poke(0x12000, 0x12)
      bus.poke(0xd506, 0x40)
      expect(bus.vic.vic_bank.peek(0x2000)).to eq(0x12)
    end
  end
end
