# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::Bus do
  subject(:bus) { bus_for(model_name) }

  let(:model_name) { "8032" }
  let(:ram_kb) { nil }
  let(:keyboard_pia) { Badline::Chips::PIA.new }
  let(:ieee_pia) { Badline::Chips::PIA.new }
  let(:crtc) { Badline::Chips::CRTC.new }

  def bus_for(name)
    model = Badline::PET::Model.named(name)
    described_class.new(model:, ram_kb: ram_kb || model.ram_kb, editor: model.editor_50hz, pia1: keyboard_pia,
                        pia2: ieee_pia, via: Badline::PET::VIA.new(start: 0xe800), crtc:)
  end

  # What a read of +addr+ finds just after the bus carried +last+.
  def read_after(last, addr)
    bus.poke(0x0000, last)
    bus.peek(addr)
  end

  it "reads back RAM" do
    bus.poke(0x7fff, 0x5a)
    expect(bus.peek(0x7fff)).to eq(0x5a)
  end

  context "with 16K of RAM" do
    let(:ram_kb) { 16 }

    it "reads the last byte on the bus above it" do
      expect(read_after(0x42, 0x4000)).to eq(0x42)
    end
  end

  it "reads the last byte on the bus from the empty sockets at $9000-$AFFF" do
    expect(read_after(0x99, 0x9000)).to eq(0x99)
  end

  it "reads BASIC 4 from $B000" do
    expect(bus.peek(0xb000)).to eq(Badline::ROM.read("pet/basic4.rom").first)
  end

  it "reads the editor from $E000 and the KERNAL from $F000" do
    expect([bus.peek(0xe000), bus.peek(0xfffc)]).to eq([Badline::ROM.read("pet/editor4-80-b-50hz.rom").first, 0x16])
  end

  it "reads the last byte on the bus at $E900-$EFFF" do
    expect(read_after(0x37, 0xe900)).to eq(0x37)
  end

  it "lets writes to ROM go nowhere" do
    bus.poke(0xc000, 0x00)
    expect(bus.peek(0xc000)).to eq(Badline::ROM.read("pet/basic4.rom")[0x1000])
  end

  describe "the screen RAM" do
    it "is 2K at $8000-$87FF on the 8032" do
      bus.poke(0x87ff, 0x51)
      expect([bus.peek(0x87ff), bus.peek(0x83ff)]).to eq([0x51, 0x00])
    end

    it "leaves $8800-$8FFF empty on the 8032" do
      expect(read_after(0x66, 0x8800)).to eq(0x66)
    end

    context "with the 4032's 40 columns" do
      let(:model_name) { "4032" }

      it "repeats 1K twice" do
        bus.poke(0x8001, 0x21)
        expect([bus.peek(0x8401), read_after(0x00, 0x8801)]).to eq([0x21, 0x00])
      end
    end

    context "with the 2001's" do
      let(:model_name) { "2001" }

      it "repeats 1K four times through $8FFF" do
        bus.poke(0x8c02, 0x13)
        expect(bus.peek(0x8002)).to eq(0x13)
      end
    end
  end

  describe "the BASIC 2 boards" do
    let(:model_name) { "3032" }

    it "leave $B000 empty" do
      expect(read_after(0xb0, 0xb000)).to eq(0xb0)
    end

    it "have no CRTC at $E880" do
      expect(read_after(0xe8, 0xe880)).to eq(0xe8)
    end
  end

  describe "the I/O page" do
    it "reads the last byte on the bus at $E800-$E80F" do
      expect(read_after(0xe8, 0xe80f)).to eq(0xe8)
    end

    it "selects PIA 1 on A4 and PIA 2 on A5, repeating their registers" do
      bus.poke(0xe81d, 0x3c)
      bus.poke(0xe821, 0x04)
      expect([keyboard_pia.cra, ieee_pia.cra]).to eq([0x3c, 0x04])
    end

    it "reads the AND of every chip a read selects" do
      keyboard_pia.poke(0x00, 0xf0)
      ieee_pia.poke(0x00, 0x3c)
      expect(bus.peek(0xe830)).to eq(0x30)
    end

    it "writes every chip a write selects" do
      bus.poke(0xe832, 0x81)
      expect([keyboard_pia.peek(0x02), ieee_pia.peek(0x02)]).to eq([0x81, 0x81])
    end

    it "selects the CRTC on A7" do
      bus.poke(0xe880, 0x0e)
      bus.poke(0xe881, 0x07)
      expect(crtc.registers[14]).to eq(0x07)
    end
  end

  describe "the 8096's expansion board" do
    let(:model_name) { "8096" }

    def control(value) = bus.poke(0xfff0, value)

    it "leaves the 8032's map alone with bit 7 clear" do
      control(0x7f)
      expect(bus.peek(0xfffc)).to eq(0x16)
    end

    it "lays banks 0 and 1 over $8000-$FFFF with bit 7 set" do
      control(0x80)
      bus.poke(0x9000, 0x11)
      bus.poke(0xc000, 0x22)
      expect([bus.peek(0x9000), bus.peek(0xc000), bus.expansion.cells[0x1000], bus.expansion.cells[0x4000]])
        .to eq([0x11, 0x22, 0x11, 0x22])
    end

    it "picks banks 2 and 3 with bits 2 and 3" do
      control(0x8c)
      bus.poke(0x8000, 0x33)
      bus.poke(0xe800, 0x44)
      expect([bus.expansion.cells[0x8000], bus.expansion.cells[0xe800]]).to eq([0x33, 0x44])
    end

    it "shows the screen through with bit 5" do
      control(0xa0)
      bus.poke(0x8000, 0x55)
      expect([bus.screen.cells[0], bus.expansion.cells[0]]).to eq([0x55, 0x00])
    end

    it "shows the I/O page through with bit 6" do
      control(0xc0)
      bus.poke(0xe811, 0x3c)
      expect(keyboard_pia.cra).to eq(0x3c)
    end

    it "protects the low bank from writes with bit 0 and the high one with bit 1" do
      control(0x83)
      bus.poke(0x8000, 0x66)
      bus.poke(0xc000, 0x77)
      expect([bus.peek(0x8000), bus.peek(0xc000)]).to eq([0x00, 0x00])
    end

    it "writes $FFF0 into the bank it was in before the write" do
      control(0x80)
      control(0x88)
      expect([bus.expansion.cells[0x7ff0], bus.expansion.cells[0xfff0]]).to eq([0x88, 0x00])
    end

    it "starts as an 8032 after a reset" do
      control(0x80)
      bus.reset!
      expect(bus.peek(0xfffc)).to eq(0x16)
    end
  end

  describe "the debug register" do
    # The bytes the debug register took from +writes+, address and value
    # pairs poked in turn.
    def debug_writes(*writes)
      written = []
      bus.install_debug_register { |value| written << value }
      writes.each_slice(2) { |addr, value| bus.poke(addr, value) }
      written
    end

    it "takes a write to $8BFF" do
      expect(debug_writes(0x8bff, 0xff)).to eq([0xff])
    end

    context "with the 2001's screen RAM there" do
      let(:model_name) { "2001" }

      it "keeps the write from the screen" do
        expect([debug_writes(0x8bff, 0x01), bus.screen.cells[0x3ff]]).to eq([[0x01], 0x00])
      end

      it "passes the page's other writes on to the screen" do
        expect([debug_writes(0x8bfe, 0x41), bus.screen.cells[0x3fe]]).to eq([[], 0x41])
      end
    end

    context "with the 8096's banks laid over it" do
      let(:model_name) { "8096" }

      it "still takes the write" do
        expect([debug_writes(0xfff0, 0x80, 0x8bff, 0x01), bus.expansion.cells[0x0bff]]).to eq([[0x01], 0x00])
      end
    end
  end
end
