# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4::Bus do
  subject(:bus) { machine.bus }

  let(:machine) { Badline::Plus4.new }
  let(:basic) { Badline::ROM.read("plus4/basic.rom") }
  let(:kernal) { Badline::ROM.read("plus4/kernal-pal.rom") }
  let(:function_low) { Badline::ROM.read("plus4/function-low.rom") }

  it "reads BASIC and the KERNAL at power-on" do
    expect([bus.peek(0x8000), bus.peek(0xfffc)]).to eq([basic[0], kernal[0x3ffc]])
  end

  it "writes to the RAM under ROM" do
    bus.poke(0x9000, 0x5a)
    expect([bus.peek(0x9000), bus.ram.peek(0x9000)]).to eq([basic[0x1000], 0x5a])
  end

  it "reads RAM at $8000-$FFFF after a write to $FF3F" do
    bus.poke(0x9000, 0x5a)
    bus.poke(0xff3f, 0)
    expect([bus.peek(0x9000), machine.ted.peek(0xff13) & 0x01]).to eq([0x5a, 0])
  end

  it "keeps the TED at $FF00 with RAM selected" do
    bus.poke(0xff3f, 0)
    bus.poke(0xff0b, 0x42)
    expect(bus.peek(0xff0b)).to eq(0x42)
  end

  it "selects ROM again on a write to $FF3E" do
    bus.poke(0xff3f, 0)
    bus.poke(0xff3e, 0)
    expect(bus.peek(0x8000)).to eq(basic[0])
  end

  it "picks the low ROM bank from the address written in the bank latch" do
    bus.poke(0xfdd1, 0)
    expect([bus.low_bank, bus.high_bank, bus.peek(0x8000)]).to eq([1, 0, function_low[0]])
  end

  it "picks the high ROM bank from its bits 2 and 3" do
    bus.poke(0xfdd4, 0)
    expect([bus.low_bank, bus.high_bank]).to eq([0, 1])
  end

  it "keeps the KERNAL's page at $FC00 in any high bank" do
    bus.poke(0xfdd8, 0)
    expect(bus.peek(0xfc00)).to eq(kernal[0x3c00])
  end

  it "reads an empty bank as the last byte on the bus" do
    bus.poke(0xfdda, 0)
    bus.poke(0x0002, 0x77)
    expect(bus.peek(0x8000)).to eq(0x77)
  end

  describe "the TED's fetches" do
    it "read the video matrix from ROM where the CPU sees ROM" do
      bus.poke(0x8000, 0x5a)
      expect(bus.ted_fetch(0x8000)).to eq(basic[0])
    end

    it "read the video matrix from RAM where the CPU sees RAM" do
      bus.poke(0x8000, 0x5a)
      bus.poke(0xff3f, 0)
      expect(bus.ted_fetch(0x8000)).to eq(0x5a)
    end

    it "read ROM under the I/O pages" do
      expect(bus.ted_fetch(0xff00)).to eq(kernal[0x3f00])
    end

    it "read character data from RAM whatever the CPU sees" do
      bus.poke(0xd000, 0x5a)
      expect(bus.ted_pattern_fetch(0xd000, false)).to eq(0x5a)
    end

    it "read character data from the KERNAL ROM when asked for ROM" do
      bus.poke(0xff3f, 0)
      expect(bus.ted_pattern_fetch(0xd008, true)).to eq(kernal[0x1008])
    end

    # Pinned by Plus/4 openmem's readme and its photo of a real Plus/4.
    it "find the last byte on the bus when asked for ROM below $8000" do
      bus.poke(0x2000, 0x11)
      bus.poke(0x0002, 0x77)
      expect(bus.ted_pattern_fetch(0x2000, true)).to eq(0x77)
    end

    it "leave the byte they fetch on the bus" do
      bus.poke(0x2000, 0x11)
      bus.poke(0x0002, 0x77)
      bus.ted_pattern_fetch(0x2000, false)
      expect(bus.data).to eq(0x11)
    end
  end

  it "puts the keyboard's 6529 at $FD30" do
    bus.poke(0xfd30, 0xfe)
    expect([machine.keyboard_port.output, bus.peek(0xfd3f)]).to eq([0xfe, 0xfe])
  end

  it "reads the ACIA's status at $FD01" do
    expect(bus.peek(0xfd01)).to eq(0x10)
  end

  it "calls the debug register's handler with a byte written to $FDCF" do
    codes = []
    bus.install_debug_register { |code| codes << code }
    bus.poke(0xfdcf, 0x42)
    expect(codes).to eq([0x42])
  end

  it "leaves $FEC0-$FEFF open without a TCBM interface" do
    bus.poke(0xfef3, 0xff)
    bus.poke(0xfef0, 0x55)
    bus.poke(0x0002, 0x66)
    expect(bus.peek(0xfef0)).to eq(0x66)
  end

  context "with a TCBM interface" do
    let(:machine) { Badline::Plus4.new(tcbm: true) }

    it "puts drive 8's TIA at $FEE0 and drive 9's at $FEC0" do
      bus.poke(0xfef3, 0xff)
      bus.poke(0xfef0, 0x55)
      bus.poke(0xfec3, 0xff)
      bus.poke(0xfec0, 0x66)
      expect([machine.tias[0].ports[0], machine.tias[1].ports[0]]).to eq([0x55, 0x66])
    end
  end

  describe "a cartridge" do
    before { bus.attach_cartridge([Badline::Storage::CRTFile::Chip.new(0, 0, 0x8000, [0x11] * 0x1000)]) }

    it "goes in cartridge 1's low slot, repeated through the bank" do
      bus.poke(0xfdd2, 0)
      expect([bus.peek(0x8000), bus.peek(0xbfff)]).to eq([0x11, 0x11])
    end
  end

  context "with 16K of RAM" do
    let(:machine) { Badline::Plus4.new(model: "c16") }

    it "repeats it through the 64K" do
      bus.poke(0x1234, 0x5a)
      bus.poke(0xff3f, 0)
      expect([bus.peek(0x5234), bus.peek(0xd234)]).to eq([0x5a, 0x5a])
    end

    it "reads an empty function ROM socket as the last byte on the bus" do
      bus.poke(0xfdd1, 0)
      bus.poke(0x0002, 0x66)
      expect(bus.peek(0x8000)).to eq(0x66)
    end

    it "has no ACIA" do
      bus.poke(0x0002, 0x55)
      expect(bus.peek(0xfd01)).to eq(0x55)
    end

    it "reads the cassette sense high on bit 2 of $FD10-$FD1F with the deck's keys up" do
      bus.poke(0x0002, 0x50)
      expect(bus.peek(0xfd1f)).to eq(0x54)
    end

    it "reads the cassette sense low with PLAY down" do
      machine.datasette.play!
      bus.poke(0x0002, 0xff)
      expect(bus.peek(0xfd10)).to eq(0xfb)
    end
  end
end
