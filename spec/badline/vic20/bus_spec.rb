# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::Bus do
  subject(:bus) { described_class.new(vic:, via1: user_via, via2: keyboard_via, blocks:) }

  let(:vic) { Badline::Memory.new([], length: 0x100, start: 0x9000) }
  let(:user_via) { Badline::VIA.new(start: 0x9000) }
  let(:keyboard_via) { Badline::VIA.new(start: 0x9000) }
  let(:blocks) { [] }

  describe "the internal RAM" do
    it "holds 1K from $0000" do
      bus.poke(0x03ff, 0x5a)
      expect(bus.ram.peek(0x03ff)).to eq(0x5a)
    end

    it "holds 4K from $1000" do
      bus.poke(0x1fff, 0xa5)
      expect(bus.peek(0x1fff)).to eq(0xa5)
    end
  end

  describe "the ROMs" do
    it "puts the KERNAL's reset vector at $FFFC" do
      expect(bus.peek16(0xfffc)).to eq(0xfd22)
    end

    it "puts BASIC at $C000" do
      expect(bus.peek(0xc000)).to eq(Badline::ROM.read("vic20/basic.rom").first)
    end

    it "puts the character ROM at $8000" do
      expect(bus.peek(0x8fff)).to eq(Badline::ROM.read("vic20/character.rom").last)
    end

    it "ignores writes" do
      bus.poke(0xe000, 0x00)
      expect(bus.peek(0xe000)).to eq(Badline::ROM.read("vic20/kernal-pal.rom").first)
    end

    it "loads the KERNAL it is given" do
      bus = described_class.new(vic:, via1: user_via, via2: keyboard_via, kernal: "vic20/kernal-ntsc.rom")
      expect(bus.peek(0xe475)).to eq(Badline::ROM.read("vic20/kernal-ntsc.rom")[0x0475])
    end
  end

  describe "an unexpanded machine" do
    it "reads the V-bus's last byte in the 3K hole" do
      bus.poke(0x1234, 0x42)
      bus.peek(0x1234)
      expect(bus.peek(0x0400)).to eq(0x42)
    end

    it "keeps the V-bus's last byte through an access elsewhere" do
      bus.peek(0x8000)
      bus.peek(0xc000)
      expect(bus.peek(0x0fff)).to eq(Badline::ROM.read("vic20/character.rom").first)
    end

    it "ignores writes to the 3K hole" do
      bus.poke(0x0400, 0x99)
      expect(bus.ram.peek(0x0400)).to eq(0)
    end

    it "reads the CPU's last byte in the empty blocks" do
      bus.peek(0xc000)
      expect([0x2000, 0x4000, 0x6000, 0xa000].map { |addr| bus.peek(addr) }).to all(eq(0x78))
    end

    it "reads the last byte written in the empty blocks" do
      bus.poke(0x7fff, 0x3c)
      expect(bus.peek(0xbfff)).to eq(0x3c)
    end

    it "reads the CPU's last byte at I/O 2 and I/O 3" do
      bus.poke(0x1000, 0x17)
      expect([0x9800, 0x9fff].map { |addr| bus.peek(addr) }).to eq([0x17, 0x17])
    end
  end

  describe "the RAM configurations" do
    {
      unexpanded: [], "3k": [0x0400], "8k": [0x2000], "16k": [0x2000, 0x4000],
      "24k": [0x2000, 0x4000, 0x6000], "32k": [0x2000, 0x4000, 0x6000, 0xa000]
    }.each do |name, filled|
      it "fills #{filled.map { |addr| format('$%04X', addr) }.join(', ').then { |s| s.empty? ? 'nothing' : s }} " \
         "for #{name}" do
        bus.blocks = described_class::RAM_CONFIGURATIONS.fetch(name)
        expect(bus.blocks.map { |block| described_class::BLOCKS.fetch(block).first << 8 }).to eq(filled)
      end
    end
  end

  describe "an expansion block" do
    let(:blocks) { %i[ram123 blk5] }

    it "holds RAM through its whole range" do
      bus.poke(0x0fff, 0x11)
      bus.poke(0xbfff, 0x22)
      expect([bus.peek(0x0fff), bus.peek(0xbfff)]).to eq([0x11, 0x22])
    end

    it "empties when taken out" do
      bus.poke(0xa000, 0x33)
      bus.blocks = %i[ram123]
      bus.peek(0xc000)
      expect(bus.peek(0xa000)).to eq(0x78)
    end

    it "reports which blocks hold RAM" do
      expect(%i[ram123 blk1 blk5].map { |block| bus.ram?(block) }).to eq([true, false, true])
    end
  end

  describe "colour RAM" do
    it "stores four bits" do
      bus.poke(0x9400, 0xfe)
      expect(bus.color_ram.nibble(0x9400)).to eq(0x0e)
    end

    it "reads the V-bus's high four lines above them" do
      bus.poke(0x97ff, 0x05)
      bus.poke(0x1000, 0xa0)
      expect(bus.peek(0x97ff)).to eq(0xa5)
    end
  end

  describe "I/O 0" do
    it "puts the VIC at $9000" do
      bus.poke(0x900f, 0x1b)
      expect(vic.peek(0x900f)).to eq(0x1b)
    end

    it "puts VIA 1 at $9110" do
      bus.poke(0x9112, 0x3c)
      expect(user_via.peek(0x9002)).to eq(0x3c)
    end

    it "puts VIA 2 at $9120" do
      bus.poke(0x9123, 0xc3)
      expect(keyboard_via.peek(0x9003)).to eq(0xc3)
    end

    it "selects VIA 1 by A4 alone" do
      user_via.poke(0x9002, 0x77)
      expect([0x9152, 0x9392].map { |addr| bus.peek(addr) }).to eq([0x77, 0x77])
    end

    it "selects VIA 2 by A5 alone" do
      keyboard_via.poke(0x9002, 0x66)
      expect([0x9162, 0x93a2].map { |addr| bus.peek(addr) }).to eq([0x66, 0x66])
    end

    it "writes to both VIAs where A4 and A5 are set" do
      bus.poke(0x9132, 0x5a)
      expect([user_via.peek(0x9002), keyboard_via.peek(0x9002)]).to eq([0x5a, 0x5a])
    end

    it "reads the AND of both VIAs where A4 and A5 are set" do
      user_via.poke(0x9002, 0xf0)
      keyboard_via.poke(0x9002, 0x3c)
      expect(bus.peek(0x9132)).to eq(0x30)
    end

    it "reads the AND of the VIC and a VIA in the VIC's range" do
      vic.poke(0x9012, 0x0f)
      user_via.poke(0x9002, 0x3c)
      expect(bus.peek(0x9012)).to eq(0x0c)
    end

    it "reads the CPU's last byte where no chip answers" do
      bus.poke(0x1000, 0x29)
      expect([0x9100, 0x914f, 0x93cf].map { |addr| bus.peek(addr) }).to all(eq(0x29))
    end
  end
end
